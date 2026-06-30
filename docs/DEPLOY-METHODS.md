# Deploying SeqtoID — the two deploy methods

There are **two, and only two, ways to deploy** — pick the one that matches your intent. Each can be run from
a **GitHub button** or **locally**, and both invocations call the *same* underlying script (so they can't drift).

| You want to… | Use | Destructive? |
|---|---|---|
| **Deploy my web-app changes** (the everyday case) | **Path A — Deploy** (`bin/deploy`) | **No** — migrate-only |
| **Rebuild the whole environment from scratch** (incl. wiping + rebuilding the DB) | **Path B — Rebuild** (`bin/rebuild_system`) | **YES — destroys the database** |

> If you are not deliberately trying to destroy and rebuild a database, you want **Path A**.

---

## Path A — Deploy my web-app changes (everyday, safe)

**What it does:** runs database **migrations only** (`db:migrate:with_data` — non-destructive), then rolls the
services (web, resque workers + scheduler + monitors, shoryuken) to the new image. It **never** drops, recreates,
seeds, reloads taxon data, or touches OpenSearch. There is no destructive operation in this path.

**Run it from GitHub (button):**
1. Actions → **Deploy** → *Run workflow*.
2. Fill in: `source` (branch to deploy), `destination` (`dev` / `staging` / `sandbox`), `release_notes` (reason).
3. Prod is intentionally **not** selectable here — prod goes through the promotion chain
   (**Deploy — promote**, `deploy-promote.yml`), which gates prod on a green dev → staging.

**Run it locally:**
```bash
# from the repo root, with AWS credentials for the target account
./bin/deploy <env> <image_tag> "<your name>"
# e.g.
./bin/deploy dev sha-abc1234 "Tom"
```
`<image_tag>` is a built image, e.g. `sha-abc1234` (never `latest`).

---

## Path B — Rebuild the system from scratch (rare, guarded, DESTRUCTIVE)

**What it does, in order:**
1. **Database rebuild** — `db:drop` → `db:create` → `db:migrate:with_data` → `seed:migrate`. **All existing data
   in the target environment is destroyed.**
2. **Taxon data reload (AUTOMATED)** — `taxon_lineage_slice:*` + `load_taxon_descriptions`. This used to be a
   manual step; it is now automatic. The taxon-descriptions S3 URI is configurable via
   `TAXON_DESCRIPTIONS_S3_URI` (don't hand-edit the script).
3. **OpenSearch** — (re)creates the `pipeline_runs` and `scored_taxon_counts` index templates, indexes, and aliases.
4. **Admin (optional, non-prod only)** — set `REBUILD_CREATE_ADMIN="email,password"` to create an admin user.
5. **Roll services** — delegates to `bin/deploy` (one canonical service-roll, no duplicated logic).

**Safety guards (an accidental rebuild is intentionally near-impossible):**
- You must **confirm the environment name** — typed interactively, or `REBUILD_CONFIRM=<env>` non-interactively.
- **Production** additionally requires `REBUILD_PROD_APPROVED=yes` **and** (in CI) the protected `prod`
  environment's required-reviewer approval.
- The image tag must be a real `sha-<hex>` build (not `latest`).

**Run it from GitHub (button):**
1. Actions → **Rebuild system (DESTRUCTIVE)** → *Run workflow*.
2. Fill in: `destination` (env to wipe + rebuild), `image_tag` (`sha-…`), `confirm_destroy` (**type the env name
   again**), `release_notes`. For prod, also set `prod_approved` = `yes`.
3. The run is blocked unless `confirm_destroy` exactly matches `destination` (and, for prod, `prod_approved=yes`
   plus the reviewer gate).

**Run it locally:**
```bash
# interactive — you'll be prompted to type the env name to confirm
./bin/rebuild_system <env> <image_tag> "<your name>"

# non-interactive (e.g. scripted dev rebuild)
REBUILD_CONFIRM=dev ./bin/rebuild_system dev sha-abc1234 "Tom"

# production rebuild (rarely, deliberately)
REBUILD_CONFIRM=prod REBUILD_PROD_APPROVED=yes ./bin/rebuild_system prod sha-abc1234 "Tom"

# optional: also create a non-prod admin, or point at a different taxon dataset
REBUILD_CONFIRM=dev REBUILD_CREATE_ADMIN="me@example.com,password" \
  TAXON_DESCRIPTIONS_S3_URI=s3://…/taxid2description.json \
  ./bin/rebuild_system dev sha-abc1234 "Tom"
```

---

## Which do I use?

```
Did I change app code / want the latest build out?      → Path A (Deploy)
Do I need a clean environment with a fresh database?     → Path B (Rebuild)   ← destroys data
Am I unsure?                                             → Path A. It cannot destroy data.
```

## Notes
- **Auto-deploy-on-push is intentionally OFF** for now — deploys are button/script-triggered while the platform is
  being hardened. (`build-docker-image.yml`'s push trigger stays commented out.)
- **`bin/manual_deploy_scripts/deploy-web.sh` is retired** — it hand-toggled `db:drop` and the taxon/OpenSearch
  steps, which is exactly the foot-gun this two-path model removes. Do not resurrect it; use Path A or Path B.
- Blue/green (Argo Rollouts) is a separate, later effort and not required for either path here.
