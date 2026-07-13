# Allowed Pipeline Outputs Policy

Status: DRAFT -- pending counsel + UCSF sign-off
Ticket: CZID-524 (define allowed pipeline outputs)
Owner: Platform / UCSF go-live (Milestone 050/091 class)
Last updated: 2026-07-08

## 1. Purpose and scope

This policy defines WHICH pipeline outputs may be released (downloaded by users)
versus which are RESTRICTED (intermediate/non-released artifacts that stay
internal to the pipeline). It bounds what leaves the platform and is a UCSF
go-live requirement.

Scope: outputs produced by the mNGS, consensus genome (CG), AMR, and benchmark
workflows, exposed through (a) bulk downloads and (b) single-file downloads.

## 2. Classification model

Every output falls into one of three release classes:

| Class | Meaning | Releasable? |
|-------|---------|-------------|
| Released report | Human/analysis-facing result (taxon report, AMR report, CG stats, overviews, coverage viz) | YES |
| Released raw/result data | Non-host reads/contigs, consensus genome FASTA, comprehensive metrics | YES (to authorized users) |
| Restricted intermediate | Host-filtered reads, alignment intermediates, stage-1 outputs, "intermediate output files" | NO (internal only) |

The existing bulk-download catalog already tags each type with a `category`
(`"reports"`, `"raw_data"`, `"results"`); this policy maps those categories onto
the release classes above and additionally names the restricted intermediates.

## 3. Allowed (releasable) outputs

### 3.1 Bulk downloads (`BulkDownloadTypesHelper::BULK_DOWNLOAD_TYPES`)
Releasable to authorized users (owner / project collaborator, subject to the
per-type `uploader_only` / `collaborator_only` / `admin_only` /
`required_allowed_feature` flags already enforced by
`BulkDownloadsController#types`):

- Reports: `sample_metadata`, `sample_overview`, `sample_taxon_report`,
  `combined_sample_taxon_results`, `contig_summary_report`, `host_gene_counts`,
  `biom_format`, `amr_results_bulk_download`, `amr_combined_results_bulk_download`,
  `consensus_genome_overview`.
- Raw/result data: `original_input_file` (uploader only), `reads_non_host`,
  `contigs_non_host`, `unmapped_reads`, `amr_contigs_bulk_download`,
  `consensus_genome`.

### 3.2 Single-file downloads
Releasable per-file endpoints already gate on a fixed allow-list (a `case` on the
requested `downloadType` that 404s anything unrecognized):
- `WorkflowRunsController#amr_report_downloads`: `comprehensive_amr_metrics_tsv`,
  `non_host_reads`, `non_host_contigs`, `zip_link`, `report_csv`.
- `WorkflowRunsController#cg_report_downloads`: `ref_fasta`.
- `WorkflowRunsController#benchmark_report_downloads`: `report_html`, `report_ipynb`.
- `WorkflowRunsController#amr_gene_level_downloads`: `download-contigs`, `download-reads`.
- Sample mNGS files (`contigs_fasta`, `nonhost_fasta`, `unidentified_fasta`, etc.).

## 4. Restricted (non-released) outputs

Restricted = intermediate/internal; MUST NOT be released to non-owners:
- Host-filtering / stage-1 outputs for mNGS. Already enforced at the app layer:
  `SfnPipelineDataService#remove_host_filtering_urls` strips stage-1 URLs for
  non-owners, gated by `PipelineRun#can_see_stage1_results`
  (`current_user.id == sample.user_id`). The owner-only `raw_results_folder`
  endpoint is the only path to raw stage-1 files.
- `consensus_genome_intermediate_output_files` -- the one bulk-download type
  explicitly named "Intermediate Output Files". Seeded into the code integration
  point (see section 5).
- Any alignment/assembly intermediates not enumerated in section 3.

## 5. Enforcement mechanisms and integration points

1. **Catalogued-type allow-list (wired -- CZID-524).**
   `BulkDownload` now validates `download_type` against
   `BulkDownloadTypesHelper::VALID_BULK_DOWNLOAD_TYPES` at the single model choke
   point, so a crafted `create` request cannot request an uncatalogued /
   unknown output type. This covers both the `types` listing and the `create`
   path (the latter previously did not re-validate the requested type).

2. **Release-restriction classification (wired as integration point -- CZID-524).**
   `BulkDownloadTypesHelper::RELEASE_RESTRICTED_BULK_DOWNLOAD_TYPES` +
   `BulkDownloadTypesHelper.release_restricted?(type)` represent, in code, the
   set of restricted intermediate types from section 4. The AUTHORITATIVE
   contents of that set are a counsel/product decision (this policy). The
   constant is seeded with `consensus_genome_intermediate_output_files` and is
   the hook to extend. Turning classification into active filtering (e.g.
   hiding restricted types from non-admins in `BulkDownloadsController#types`, or
   rejecting them in `create`) is intentionally left as a gated follow-up so
   behavior does not change before counsel finalizes the list -- see open items.

3. **Existing per-file allow-lists (already present).**
   The `WorkflowRunsController` `case`-based download endpoints and the mNGS
   stage-1 URL stripping remain the enforcement for single-file downloads.

## 6. Open items (counsel / product)

- [ ] Counsel/product to finalize the authoritative restricted-intermediate set
      and confirm which `raw_data` types are releasable to collaborators vs owners only.
- [ ] Decide whether to activate release-restriction filtering (gated) in
      `BulkDownloadsController#types` / `create` for non-admin users, using
      `BulkDownloadTypesHelper.release_restricted?`.
- [ ] Related, NOT in scope here: access & permissions model (CZID-521/522) --
      a design pass defines WHO may download WHICH class; this policy defines WHAT
      is releasable.
