# Data Retention Policy

Status: DRAFT -- pending counsel + UCSF sign-off
Ticket: CZID-519 (define); implemented by CZID-520 (app enforcement) + AWS S3 lifecycle (infra-gated)
Owner: Platform / UCSF go-live (Milestone 050/091 class)
Last updated: 2026-07-08

## 1. Purpose and scope

This policy defines how long each class of data in the seqtoid-web platform is
retained, when and how it is purged, and which controls enforce that. It exists
to satisfy UCSF go-live data-governance requirements and to bound the platform's
storage of sequencing inputs, intermediate artifacts, and results.

Scope: all persistent data stored by the seqtoid-web application and its backing
stores -- the relational database (samples, runs, metadata, deletion logs) and
the S3 buckets that hold pipeline inputs, intermediate files, and outputs. It
does NOT cover application/audit logs, backups, or compliance-evidence records,
which are governed separately (see section 6).

## 2. Data classes

| # | Data class | Store | Description |
|---|------------|-------|-------------|
| 1 | Raw input files | S3 (`SAMPLES_BUCKET_NAME/.../fastqs`) | User-uploaded FASTQ/FASTA sequencing reads. |
| 2 | Intermediate files | S3 (run `s3_output_prefix`, host-filter/alignment stages) | Non-released pipeline byproducts: host-filtered reads, alignment intermediates, stage-1 outputs. |
| 3 | Released outputs | S3 (run `s3_output_prefix`, report/results steps) | Releasable results: taxon reports, consensus genomes, AMR reports, coverage viz, contigs. See ALLOWED-PIPELINE-OUTPUTS-POLICY.md (CZID-524). |
| 4 | Sample & run metadata | DB (`samples`, `pipeline_runs`, `workflow_runs`) | Row-level metadata: names, timestamps, status, `s3_output_prefix`, sample metadata fields. |
| 5 | Bulk downloads | DB (`bulk_downloads`) + S3 | Generated download archives. |
| 6 | User accounts | DB (`users`) + Auth0 | Account records and authentication identity. |
| 7 | Compliance evidence | DB (export-control attestations/clearances) | Retained deliberately -- see section 6. |
| 8 | Deletion logs | DB (`deletion_logs`) | Audit trail of soft/hard deletions (GDPR evidence). |

## 3. Retention windows

The default platform retention window for sample-derived pipeline data (classes
1, 2, 3, and the runs/metadata that reference them) is **90 days** from run
creation, unless a project or agreement specifies otherwise. This is the
"90-day rule" referenced by the UCSF requirement.

| Data class | Retention window | Mechanism |
|------------|------------------|-----------|
| Raw input files (1) | 90 days | App enforcement (CZID-520) cascades S3 cleanup via run/sample `destroy` callbacks; S3 lifecycle as backstop. |
| Intermediate files (2) | 90 days (may be purged EARLIER -- see 4.1) | Same as above. |
| Released outputs (3) | 90 days | Same as above. |
| Sample & run metadata (4) | 90 days (tied to the run) | App enforcement soft-deletes then hard-deletes rows. |
| Bulk downloads (5) | 7 days | Existing `DeleteOldBulkDownloads` job (`BulkDownload::AUTO_DELETE_AFTER_NUM_DAYS`). |
| User accounts -- unclaimed (6) | Deleted at 21 days; MUST NOT be retained past 30 days | Existing `DeleteUnclaimedUserAccounts` job. |
| Compliance evidence (7) | Retained (NOT auto-purged) | See section 6. |
| Deletion logs (8) | Retained for audit | Not purged by retention enforcement. |

Notes:
- The 90-day window is configurable per deployment via the `DATA_RETENTION_DAYS`
  AppConfig key (CZID-520). A configured value below a hard floor
  (`EnforceDataRetention::MIN_RETENTION_DAYS`, currently 30 days) is rejected by
  the enforcement job so a misconfiguration cannot purge recent data.
- Age is measured from run `created_at`.

## 4. Output vs intermediate handling

### 4.1 Intermediate files
Intermediate files (class 2) are non-released byproducts and carry no
independent retention value. They are already hidden from non-owners at the
application layer (stage-1 / host-filtering URLs are stripped for non-owners --
see `SfnPipelineDataService#remove_host_filtering_urls` and
`PipelineRun#can_see_stage1_results`). They MAY be purged earlier than 90 days
if an earlier-cleanup mechanism is introduced; they MUST NOT outlive the run
they belong to.

### 4.2 Released outputs
Released outputs (class 3) are what the platform exposes for download. The
authoritative allow-list of which outputs are releasable vs restricted is
defined in `ALLOWED-PIPELINE-OUTPUTS-POLICY.md` (CZID-524). Released outputs are
retained for the full 90-day window and purged with their run.

### 4.3 Deletion is cascading and logged
When a run/sample is purged, deletion cascades to all associated S3 prefixes via
the model `before_destroy`/`after_destroy` callbacks (`cleanup_s3` ->
`S3Util.delete_s3_prefix`), and a `DeletionLog` row is written for audit. The
retention enforcement job reuses this vetted path rather than deleting S3
directly.

## 5. Enforcement mechanisms

Two complementary layers enforce retention:

1. **Application enforcement (authoritative) -- CZID-520.**
   The `EnforceDataRetention` scheduled job (`app/jobs/enforce_data_retention.rb`)
   finds runs older than the retention window and routes them through the
   existing `BulkDeletionService` (soft delete -> `DeletionLog` -> async
   `HardDeleteObjects` -> S3 cleanup). Fail-safe design:
   - Dry-run by DEFAULT; deletes only when `ENABLE_DATA_RETENTION_ENFORCEMENT`
     is `"1"` and the `DATA_RETENTION_DRY_RUN` ENV kill-switch is not set.
   - Refuses to run with a window below the floor.
   - Caps objects deleted per run (blast-radius guard).

2. **S3 lifecycle rules (backstop) -- AWS-gated.**
   Bucket-level S3 lifecycle rules provide defense-in-depth so that orphaned
   objects (e.g. from a failed app-side deletion) still expire. These are
   INFRASTRUCTURE and are authored/held in the infra repo (czid-infra); they are
   NOT applied by this application and require an AWS apply + platform sign-off.
   Recommended lifecycle expiration = the retention window (90 days) on the
   samples/results prefixes, with a longer floor than the app window to avoid
   racing app-side deletion. The app layer is authoritative; S3 lifecycle is a
   safety net, not a substitute.

## 6. Exclusions / do-not-purge

The following are deliberately NOT subject to retention purging:
- **Export-control compliance evidence** (attestations, clearances,
  device-location attestations). These are retained as compliance evidence and
  are marked `dependent: :restrict_with_exception` on `User`. Their
  retention/erasure policy (evidence retention vs. data-subject erasure) is a
  TODO for counsel (see `User` model notes, CZID-330/285/286).
- **Deletion logs**, retained for GDPR/audit.
- **Application and infrastructure logs / backups**, governed separately.

## 7. Open items (counsel / product / AWS)

- [ ] Counsel to confirm the 90-day window and any per-agreement overrides for UCSF.
- [ ] Counsel to confirm compliance-evidence retention vs. data-subject erasure interaction.
- [ ] Product to confirm whether intermediate files should be purged earlier than outputs.
- [ ] AWS/infra to author + apply the backstop S3 lifecycle rules (held; requires apply).
- [ ] Related, NOT in scope here: access & permissions model (CZID-521/522) -- design pass required.
