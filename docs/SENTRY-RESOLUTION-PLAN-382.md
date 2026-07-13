# Sentry cleanup (epic #382) — resolution plan

Companion to `SENTRY-ERROR-TRIAGE-2026-06-30.md`. That inventory is a **2026-06-30 snapshot**;
this note reconciles it against `origin/main` as of the dev-EKS stabilization. **Headline: nearly the
entire snapshot is already resolved in code on `main`** — the branch for this effort carries no code
diff because there was nothing left to cleanly fix in the source. What remains is Sentry-side
bookkeeping (mark resolved) and two AWS/tenant-config actions that live outside this repo.

## A / B / C triage (41 `level:error` + ~74 Info)

- **A — real code bugs**: essentially all already fixed on `main` (see mapping). Only residual: 3
  minified React `TypeError`s needing source-maps to pin the exact component (A4).
- **B — environmental bring-up artifacts** (~15): stale after dev/staging DB creation + migrations.
  No code. Verify app health, then bulk-resolve in Sentry.
- **C — Info-level `generateFetchFn` GraphQL noise** (~74): already silenced on `main` (CZID-391).

## A — real bugs: status on `main`

| Group | Issue | Status on `main` | Evidence |
|---|---|---|---|
| A1 | `Errno::ENOENT: aws` (~1,950 ev) | **FIXED** — `awscli` pinned | `requirements.txt` (`awscli==1.45.31`, CZID-146 note) |
| A2 | `Auth0::AccessDenied` api/v2 not enabled | **CONFIG (Auth0 tenant)** — not code | Enable Management API for dev/staging apps |
| A2 | `Auth0::Unsupported` 409 "already exists" | **FIXED** — rescued → graceful GraphQL error | `app/graphql/mutations/create_user.rb:22` (#384) |
| A3 | `SfnDescriptionNotFoundError` on `#results` | **FIXED** — rescue → 404 "Results not available" | `app/controllers/workflow_runs_controller.rb:54` (#385) |
| A3 | `StateMachineDoesNotExist` (dev ARN in staging acct) | **DATA/CONFIG** — `AppConfig` SFN_ARN row seeded wrong | fix the staging `AppConfig::SFN_*` value; not source |
| A4 | `InternalError: too much recursion` `sendHeartbeat` | **FIXED** — self-recursion → no-op | `app/assets/src/api/upload.ts:179` (#386) |
| A4 | 3× `TypeError` in minified report views | **RESIDUAL** — needs source-maps to pin component | see "residual" below |
| A5 | `s3:GetObjectTagging` AccessDenied (staging) | **IAM (AWS)** — not code; code already fails safe | add perm to `idseq-web-staging` role; `sample.rb` rescue at :451 |
| A6 | `JSON::ParserError` `benchmark_update` (532 ev) | **FIXED** — blank/parse guard | `lib/tasks/pipeline_monitor.rake:172` (`parse_json_or_nil`, #388) |
| A6 | `TypeError: nil into String` load_taxon_descriptions | **FIXED** — blank-path abort + nil coerce | `lib/tasks/load_taxon_descriptions.rake:14,33` (#388) |
| A6 | ES `call_lambda` / `taxon_lineage_slice` / SIGTERM / `$?` nil | **RESIL-owned** — batch/ES hardening | landed #476/#477/#484; RESIL fence, not edited here |
| A7 | `application.css` not precompiled | **FIXED** — manifest link present | `app/assets/config/manifest.js` (`link application.css`) |
| A7 | `SocketError` malformed GraphQL URL | **CONFIG** — GraphQL endpoint env var; verify then resolve | environmental |

## B — environmental bring-up artifacts (verify, then bulk-resolve in Sentry)

All are `ActiveRecord::PendingMigrationError` / `StatementInvalid: table/db doesn't exist` /
`NoDatabaseError` for `idseq_dev` / `idseq_staging` — fired before the DBs/migrations existed.
Post dev-EKS stabilization these are **stale**. Action: confirm `/health_check` + `HomeController#landing`
are green, then select-all → Resolve in Sentry. **Likely-moot list (12 issues):** the 12 rows in
"Group B" of the triage doc (DEV-RAILS-PROJECT-9/N/6/T/Q/P/S, STAGING-RAILS-PROJECT-E/A/9/C/D).

## C — Info noise: silenced on `main`

`generateFetchFn.req/res` + `[GQL Error]` Info entries (~74). Two-layer fix already merged (CZID-391):
1. **Source**: `app/assets/src/relay/environment.ts` no longer `captureMessage`s req/res or field-level
   GraphQL errors (console-only now).
2. **Defense-in-depth**: `app/assets/src/index.tsx` `beforeSend` drops residual `level:"info"`
   `generateFetchFn`/`[GQL Error]` events from older deployed bundles.
Action: bulk-resolve the existing Info entries in Sentry; new bundles won't re-emit them.

## Sentry-side resolution plan (no API/UI access from here)

1. **Resolve as fixed-by-code (A)** — confirm the current `main` bundle/image is deployed, then mark
   resolved: A1, A2-409, A3-results, A4-heartbeat, A6-benchmark, A6-taxon, A7-precompile. Regressions
   re-open automatically on a new event.
2. **Resolve as environmental (B)** — the 12 Group-B DB/migration issues: verify health, bulk-resolve.
3. **Resolve as silenced (C)** — the ~74 `generateFetchFn`/`[GQL Error]` Info entries.
4. **Keep open / route to owners (not fixable in app source):**
   - A2 `AccessDenied` — enable Auth0 Management API (v2) for the dev + staging applications.
   - A3 `StateMachineDoesNotExist` — correct the staging `AppConfig` SFN ARN (dev ARN seeded in
     staging acct).
   - A5 `s3:GetObjectTagging` — grant the perm on `idseq-web-staging` for the sandbox bucket.
   - A7 `SocketError` — fix the malformed GraphQL endpoint URL (`https:443`) in staging config.
   - A4 residual 3× `TypeError` — needs Sentry source-maps to identify the report-view components;
     then add null/shape guards. Tracked as a child ticket.
