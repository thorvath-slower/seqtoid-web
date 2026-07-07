# Taxon-lineage: cut over from the dev SLICE to the FULL lineage (Forgejo #528)

## Problem
The webapp's MySQL `taxon_lineages` table **and** its OpenSearch index are loaded from a
dev/test **slice** CSV (`ncbi-indexes-prod/2024-02-06/index-generation-2/taxon_lineages_2024_slice.csv`).
The slice omits **taxid 694009 (coronavirus)** and **~20k other taxa**, which surfaces on dev as:
- `TaxonLineage::LineageNotFoundError: Taxon lineage not found for taxid 694009` (639+ Sentry events), and
- `taxon-indexing-concurrency-manager-dev` lambda failures (`elasticsearch_query_helper#call_lambda`,
  `VisualizationsController#samples_taxons`).

The fix is to load the **full** lineage into both stores, not the slice.

> **Note on "full".** The *pipeline's* lineage is `taxid-lineages.marisa` (a binary marisa-trie,
> per the `AlignmentConfig` seeds) — that is **not** what the webapp loads. The webapp loads a **CSV**
> into MySQL. So the cutover needs a **full-lineage CSV** in `s3://seqtoid-public-references/…`. See
> Prereqs.

## What changed in code (this PR)
`lib/tasks/taxon_lineage_slice.rake` now reads the source key + version from ENV, defaulting to the
current slice (behavior unchanged unless the env is set):
- `TAXON_LINEAGE_FILE_KEY` — S3 key under `S3_DATABASE_BUCKET` (default: the slice CSV)
- `TAXON_LINEAGE_VERSION`  — lineage version for the `exists?`/`version_start` guards (default `2024-02-06`)

This makes the slice→full switch a **config + one-time reload**, no code change per env.

## Prereqs (BLOCKER — needs authenticated AWS)
Confirm the full-lineage **CSV** exists and get its exact key (anonymous access is denied; needs a
signed-in console or creds):
```
aws s3 ls s3://seqtoid-public-references/ncbi-indexes-prod/2024-02-06/index-generation-2/ | grep -i lineage
```
- **If a full CSV exists** (e.g. `taxon_lineages.csv` / `taxon_lineages_2024.csv`) → use it below.
- **If only `taxid-lineages.marisa` + the slice CSV exist** → we must first **generate a full CSV**
  from the index-generation lineage (marisa → CSV with the same header/columns as the slice) and
  upload it to that prefix. That is a separate, small data-gen step; do it before the cutover.

## Cutover (dev only — staging/prod are HELD for team approval)
The load **replaces**, it does not append — loading a same-version file on top of existing rows would
create duplicate `version_start..version_end` rows and break `TaxonLineage.versioned_lineages`. So
remove the old version's rows first.

**Option A — one-off ECS/rake task (mirrors the Refresh Reference Data GHA):**
Set `TAXON_LINEAGE_FILE_KEY=<full CSV key>` in the dev web-params, then run against the deployed task:
```
rake taxon_lineage_slice:remove_slice                    # clear the old 2024-02-06 rows
rake taxon_lineage_slice:import_data_from_s3             # load the FULL CSV (from the ENV key)
rake taxon_lineage_slice:create_taxon_lineage_slice_es_index   # rebuild OpenSearch from the full table
```

**Option B — the Refresh Reference Data GHA** (`.github/workflows/refresh-reference-data.yml`,
workflow_dispatch): run with `environment=dev`, `version=2024-02-06`, `file_key=<full CSV key>`.
⚠️ `reference_data:refresh` currently `insert_all`s without a pre-remove — either run
`taxon_lineage_slice:remove_slice` first, or add `REFERENCE_DATA_FORCE=1` **only after** a remove.
(Follow-up: give `reference_data:refresh` an explicit replace-in-place mode so a single dispatch is
safe.)

Both take ~1–2 h to load ~3M rows + ~53 min for the OpenSearch rebuild (#476/#477 bulk-load tuning
already applied in `create_taxon_lineage_slice_es_index`).

## Verify
- `TaxonLineage.where(taxid: 694009).exists?` → **true**
- Orphan-taxid anti-join = 0 (taxon_counts referencing a taxid with no lineage row)
- `TaxonLineage.count` ≈ full (~3M), not the slice's small count
- OpenSearch `taxon_lineages` index doc-count **== `TaxonLineage.count`** (the deploy hook's #476
  in-sync check)
- Sentry: `LineageNotFoundError 694009` + the taxon-indexing-lambda issues stop; a benchmark run
  passes (AUPR ≥ 0.98).

## Rollback
Repoint the env's `TAXON_LINEAGE_FILE_KEY` back to the slice key and re-run the three tasks.

## Durable follow-up (staging/prod, when unheld)
Set `TAXON_LINEAGE_FILE_KEY` to the full CSV in **all** envs' web-params so future fresh deploys load
full via the `taxon_lineage_slice:load_slice_if_needed` PreSync hook (already idempotent + in-sync
guarded). Keep it in SSOT env config, mirrored across dev/staging/prod/sandbox.
