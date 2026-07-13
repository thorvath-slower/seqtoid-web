# Taxon-lineage: cut over from the dev SLICE to the FULL lineage (Forgejo #528)

## Problem — two distinct issues
The webapp's MySQL `taxon_lineages` table **and** its OpenSearch index are loaded from a dev/test
**slice** CSV (`ncbi-indexes-prod/2024-02-06/index-generation-2/taxon_lineages_2024_slice.csv`).

1. **Issue 1 — ~20,625 latent omissions.** The slice omits ~20k taxa the full `2024-02-06` reference
   contains → any sample carrying one raises `TaxonLineage::LineageNotFoundError`. Sample-independent
   latent blast radius. **Fix: load the FULL lineage, not the slice.**
2. **Issue 2 — taxid 694009 on dev.** 694009 *is* in the slice, yet the dev lookup found no row → a
   **partial/truncated import** that the old `exists?` guard permanently masked (it skipped re-import
   once *any* row for the version existed). **Fix: reload + a row-count completeness guard.**

Both surface on dev Sentry as `LineageNotFoundError: taxid 694009` (639+ events) and
`taxon-indexing-concurrency-manager-dev` lambda failures.

## The full source (confirmed in S3)
`s3://seqtoid-public-references/ncbi-indexes-prod/2024-02-06/index-generation-2/` contains:
- `taxon_lineages_2024_slice.csv` — 691 MB — the **slice** (loaded today)
- **`versioned-taxid-lineages.csv.gz` — 99 MB gz — the FULL lineage** ← use this
- `taxid-lineages.parquet` (full, Parquet) · `taxid-lineages.marisa` (pipeline binary)

The index-generation `README` states `versioned-taxid-lineages.csv` is the file "used to populate
taxon_lineage database table" — i.e. the slice is a row-subset of it, **same schema**. (Spot-check the
header matches the `taxon_lineages` columns on first load.)

## What changed in code (PR #199)
`lib/tasks/taxon_lineage_slice.rake`:
- **ENV-configurable source** — `TAXON_LINEAGE_FILE_KEY` / `TAXON_LINEAGE_VERSION` (default = the slice,
  so behavior is unchanged until an env opts in).
- **Gzip support** — transparently gunzips a `.gz` key (the full export is gzipped).
- **Completeness guard (Issue 2)** — `load_slice_if_needed` now re-imports when the loaded row count is
  below `TAXON_LINEAGE_MIN_ROWS` (clearing the partial rows first), instead of the presence-only
  `exists?` that masked truncated loads. Unset → falls back to presence-only (unchanged).

So the slice→full switch is **config + a one-time reload**; the ES index is rebuilt from the loaded
table by the same task.

## Cutover (DEV ONLY — staging/prod HELD for team approval)
Set in the **dev** web-params:
```
TAXON_LINEAGE_FILE_KEY = ncbi-indexes-prod/2024-02-06/index-generation-2/versioned-taxid-lineages.csv.gz
TAXON_LINEAGE_MIN_ROWS = <full row count>     # from: zcat versioned-taxid-lineages.csv.gz | wc -l  (minus header)
```
Then run the one-time replace against the deployed dev task (load **replaces**, not appends — clear the
old version first or you get duplicate `version_start..version_end` rows that break
`TaxonLineage.versioned_lineages`):
```
rake taxon_lineage_slice:remove_slice                          # clear old 2024-02-06 rows
rake taxon_lineage_slice:import_data_from_s3                   # load FULL (gunzips the .gz)
rake taxon_lineage_slice:create_taxon_lineage_slice_es_index   # rebuild OpenSearch from the full table
```
Or the **Refresh Reference Data** GHA with `file_key=…/versioned-taxid-lineages.csv.gz` — but
`reference_data:refresh` still appends and doesn't gunzip; run `remove_slice` first (follow-up: give it
gunzip + replace-in-place parity with this task).

Budget ~1–2 h (load ~3M rows) + ~53 min (OpenSearch rebuild; #476/#477 bulk-load tuning already applied).
Size the taxon-load Job memory for the full uncompressed CSV (~GB, held in memory).

## Verify (all must pass)
- `TaxonLineage.where(taxid: 694009).exists?` → **true**
- Orphan anti-join = 0 — `taxon_counts` referencing a taxid with no lineage row
- `TaxonLineage.count` == the source row count (== `TAXON_LINEAGE_MIN_ROWS`); not the slice's smaller count
- OpenSearch `taxon_lineages` doc-count **== `TaxonLineage.count`** (the deploy hook's #476 in-sync check)
- Sentry: `LineageNotFoundError 694009` + the indexing-lambda issues stop; a benchmark run passes (AUPR ≥ 0.98)

## Rollback
Repoint `TAXON_LINEAGE_FILE_KEY` to the slice key (unset `TAXON_LINEAGE_MIN_ROWS`) and re-run the three tasks.

## Durable follow-up (staging/prod, when unheld) + tracked separately (#528 plan)
- Set `TAXON_LINEAGE_FILE_KEY` + `TAXON_LINEAGE_MIN_ROWS` in **all** envs' SSOT web-params so fresh
  deploys load full via the idempotent `load_slice_if_needed` PreSync hook, mirrored dev/staging/prod/sandbox.
- Separate PRs from the remediation plan: G2 `merged.dmp` taxid remap / newest-`version_end` fallback;
  G3 throttle the per-contig `log_error` (639 events → 1); zero-orphan gate in `BenchmarkWorkflowRun`.
