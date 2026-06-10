# MySQL → PostgreSQL cutover runbook

**Slice**: `improvement-#005-postgres-migration` · **Owner of execution**: Tom (Bucket B — live data)

This is the operational procedure for moving `seqtoid-web` from Aurora MySQL to
PostgreSQL. The code is already engine-portable (bugs #010/#011 rewrote all
MySQL-only SQL; the adapter is `pg`; `schema.rb` is Postgres-valid). What remains
is the **data move + switchover**, which must preserve every row (Principle V:
graceful & reversible — backup + rollback at each step).

## 0. Preconditions
- [ ] Branch `improvement-#005-postgres-migration` merged; image built on `pg`.
- [ ] A PostgreSQL 16 target exists: RDS/Aurora-PostgreSQL (cloud) or the
      CloudNativePG cluster (`deploy/postgres/cloudnativepg-cluster.yaml`, appliance).
- [ ] App can reach it; `config/database.yml` env vars set (`DB_HOST`, `DB_USERNAME`,
      `DB_PASSWORD`, `DB_SSLMODE=require`).
- [ ] A **full MySQL backup / Aurora snapshot** taken immediately before — this is
      the rollback anchor.

## 1. Create the Postgres schema
Load the converted schema (no data):
```bash
RAILS_ENV=prod bin/rails db:create db:schema:load
```
Verify the JSON columns are `jsonb` and the generated `phylo_tree_ngs.tax_id`
column exists (the rewrites depend on both):
```sql
SELECT table_name, column_name, data_type, is_generated
FROM information_schema.columns
WHERE column_name IN ('inputs_json','cached_results','tax_id')
ORDER BY table_name;
```

## 2. Move the data
Use **pgloader** (open source, handles MySQL→PG type mapping + the `text`→`jsonb`
casts) for a one-shot move, or **AWS DMS** for near-zero-downtime CDC.

pgloader one-shot (downtime window = app in maintenance mode):
```
LOAD DATABASE
  FROM mysql://USER:PASS@AURORA-MYSQL/idseq_prod
  INTO postgresql://USER:PASS@PG-HOST/idseq_prod
WITH data only, include no drop, truncate, disable triggers,
     workers = 8, concurrency = 1, batch rows = 5000
CAST type datetime to timestamptz,
     column workflow_runs.inputs_json   to jsonb using "set to jsonb",
     column workflow_runs.cached_results to jsonb using "set to jsonb",
     column phylo_tree_ngs.inputs_json  to jsonb using "set to jsonb";
```
Notes:
- `text`→`jsonb` rows MUST be valid JSON or NULL; pgloader logs casts that fail.
  Pre-scan for invalid JSON before the window (see §5).
- Skip the generated column `phylo_tree_ngs.tax_id` on load (Postgres computes it).
- After load: `ANALYZE;` so the planner has stats for the ranking/report queries.

## 3. Verify parity (gate — do not switch traffic until green)
- [ ] **Row counts** match per table: compare `SELECT count(*)` on every table.
- [ ] **Sequences** reset to `max(id)+1` (pgloader usually does; confirm):
      `SELECT setval(pg_get_serial_sequence('samples','id'), (SELECT max(id) FROM samples));` (repeat per table).
- [ ] **Parity suite** green on the Postgres prod replica:
      `bundle exec rspec spec/services/top_taxons_sql_service_spec.rb spec/services/top_taxons_sql_service_ranking_parity_spec.rb`
- [ ] **Hot-path spot check**: run the TaxonCount report for a known sample on both
      engines and diff the JSON (taxa, ranks, rpm, zscore must match).
- [ ] **JSON sort/filter** (`workflow_run` scopes) return the same ordering/membership.

## 4. Switch over (graceful — Principle V)
1. App → maintenance mode (drain in-flight requests; this pairs with the Argo
   Rollouts blue/green of slice 4).
2. Final incremental sync (DMS CDC) or confirm the one-shot window had no writes.
3. Flip `DB_HOST`/adapter env to Postgres; deploy the `pg` image green.
4. Smoke test (login, list samples, open one report, run a heatmap) on green.
5. Shift traffic green; keep MySQL **read-only, running** for the rollback window.

## 5. Rollback
- **Before traffic shift**: just point env back at MySQL; nothing changed there.
- **After shift, within window**: stop writes, point env back at MySQL (still
  intact, read-only). Postgres-side writes since cutover are lost — keep the
  window short and announced. For longer safety, run DMS CDC PG→MySQL in reverse.
- The pre-cutover MySQL snapshot (§0) is the last resort.

## 6. Pre-flight data hygiene (run days before)
```sql
-- rows whose "JSON-string" text columns are NOT valid JSON (would fail text->jsonb)
SELECT id FROM workflow_runs
WHERE inputs_json IS NOT NULL AND NOT JSON_VALID(inputs_json);   -- MySQL side
SELECT id FROM workflow_runs
WHERE cached_results IS NOT NULL AND NOT JSON_VALID(cached_results);
```
Fix or null these before the window; they're the most likely cutover failure.

## Out of scope here
- The blue/green traffic mechanics live in slice 4 (Argo Rollouts); this runbook
  assumes that gate exists for the graceful switch.
