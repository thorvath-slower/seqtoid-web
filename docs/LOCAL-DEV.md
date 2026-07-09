# Local development — fast inner loop & the no-AWS harness

This is the practical guide to iterating on `seqtoid-web` **on your laptop**, without
pushing to dev EKS and waiting on the full pipeline. Two things you want:

1. **Fast rebuilds** — don't redo gem/npm/asset work you didn't change (#463).
2. **No AWS** — run and test the app with nothing but Docker, no cloud creds (#488).

For the CI-parity test gate see [`TESTING.md`](TESTING.md); for the dev *deploy*
pipeline see [`dev-platform-runbook.md`](dev-platform-runbook.md). This doc is the
**local loop only** — nothing here touches staging or prod.

---

## The no-AWS harness (`OFFLINE=1`)

Everything below runs with **no AWS credentials**. `OFFLINE=1` is the switch:

- `make` skips `aws-oidc exec` / ECR-login and uses `web.env` for config
  (see the `docker_compose` var at the top of the `Makefile`).
- `bin/entrypoint.sh` skips Chamber secret injection (`exec bundle exec "$@"` directly)
  instead of pulling SSM secrets — so the container boots with no cloud round-trip.

```bash
export OFFLINE=1
make local-init            # one-time: build the image + set up
make local-db-setup        # create DB + load schema + seed (seeds an admin user, id=1)
make local-start-webapp    # app + webpack dev server
```

### What comes up

`docker-compose.yml` stands up the whole backing stack locally — **no LocalStack or cloud
needed** for the core loop:

| Service | Image | Purpose |
|---|---|---|
| `web` | app image | Rails app (port **3001**) |
| `web-proxy` | nginx | routes `/` → web (port **3000**) |
| `db` | `mysql:8.0` | the app **hard-requires MySQL 8** |
| `redis` | `redis:7.4` | Resque / caching |
| `opensearch` (+ dashboards) | OpenSearch 2.7 | taxon search / heatmap |
| `concurrency` / `indexing` / `eviction` lambdas | local images | the AWS-Lambda paths, run as local containers (`INDEXING_LAMBDA_MODE=local`) |

The only thing that still needs real AWS is the **S3 sample-upload** step
(`samples#upload_credentials` → STS) — that is the genuine cloud boundary; the rest of the
app runs fully offline.

### First boot: build assets, then restart web (CZID-298)

On a **fresh clone** the `web` container comes up before the production asset bundles
exist, so the landing page 500s until you build them once and restart:

```bash
docker compose exec -T web bash -lc 'npm run build-img'   # emit app/assets/dist/*.bundle.min.js
docker compose restart web                                 # pick up the fresh bundles
```

Two things make this reliable and are already wired into `docker-compose.yml`:

- The `web` service carries an **anonymous `/app/node_modules` volume** so the `.:/app`
  bind mount does not shadow the image-baked `node_modules` — otherwise `build-img`
  fails with `webpack: not found`.
- After the restart the landing + authed pages render cleanly. (For the *inner-loop*
  frontend flow use `make local-start-webapp` / `npm start` instead — see below.)

### Log in offline

Auth0 needs a client id you won't have offline. Local dev bypasses it:

- Set `ALLOW_DIRECT_USER_LOGIN=true`, then either click **Sign In** (does a local direct
  login as the seeded admin) or hit `GET /direct_user_login?user_id=1` to set the session.

### Which port?

Use **http://localhost:3000** (the nginx `web-proxy`), *not* 3001. The proxy routes the app
and the GraphQL endpoint together; hitting 3001 directly can 500 on data pages.

> `development.rb` sets `force_ssl`, so plain http redirects to https except `/health_check`.
> For raw http requests send `-H 'X-Forwarded-Proto: https'`.

---

## Fast rebuilds (the inner loop)

**You rarely need a full image rebuild.** The `web` service bind-mounts your working tree
(`.:/app`), so edits are live:

- **Ruby** — edit and refresh; `rails` reloads app code in `development`. Only
  `make local-console` + `bundle install` when you change the `Gemfile`.
- **Frontend** — `make local-start-webapp` runs `npm start` (webpack dev server, HMR).
  Edits to `app/assets/src` recompile incrementally — no image rebuild.
- **DB schema** — `make local-migrate` / `make local-db-reset`, no rebuild.

> ⚠️ **Asset gotcha:** the `.:/app` bind mount masks the image-baked `app/assets/dist`.
> If you need a production bundle locally, build it **inside the running container**
> (`docker compose exec -T web bash -lc 'npm run build-img'`), never via a throwaway
> `docker run` off the image (that compiles the image's *stale* source and silently ignores
> your host edits). Then `rm -rf tmp/cache/{assets,sprockets}` and restart `web`.

### When you *do* rebuild — the caching that's already in place

`make local-build` is already set up to avoid redoing everything:

- **BuildKit is on** for every build — the `Makefile` exports `DOCKER_BUILDKIT=1` and
  `COMPOSE_DOCKER_CLI_BUILD=1`. You get layer caching for free; an unchanged
  `Gemfile.lock` / `package-lock.json` layer is reused (no re-install at all).
- **Cache-mounts for the case where deps *do* change (#463)** — the Dockerfile
  (`# syntax=docker/dockerfile:1`) mounts the npm download store (`/root/.npm`) and the
  bundler download cache (`/usr/local/bundle/cache`) as persistent BuildKit caches. So a
  `package-lock` / `Gemfile.lock` bump re-downloads **only the new** tarballs/gems instead
  of the whole set — the biggest win right after a dependency change. Build-time only:
  installed `node_modules` + gems (`/usr/local/bundle/gems`) are still baked into the image;
  only the download caches are mount-excluded.
- **`cache_from` the last ECR image** — `docker-compose.yml` sets
  `web.build.cache_from: …/idseq-web:latest`, so a fresh clone / cold cache seeds its
  layers from the last pushed image instead of building from scratch. `make local-build`
  runs `local-ecr-login` first so the pull works.

> **Why no local `vendor/bundle` volume?** The image installs gems to the default
> `/usr/local/bundle` (there's no `BUNDLE_PATH=vendor/bundle` override), so a
> `bundle-cache:/app/vendor/bundle` volume like CI's would sit **empty** and just shadow
> the image's gems — it wouldn't speed anything. The layer cache + download cache-mounts
> above are the local gem-caching story; a persistent-installed-gems volume would need a
> repo-wide `BUNDLE_PATH` change and is deliberately deferred on #463.

The CI/build-server image build additionally uses an **ECR registry build-cache**
(`--cache-from`/`--cache-to type=registry,mode=max`) and multi-arch — that's the
`bin/build-docker` path (tracked under #482/#485), separate from this local loop.

### Fast test feedback (before you push)

You don't need Docker or the full suite for a quick sanity pass:

```bash
make check-fast    # eslint + tsc + flake8 — seconds, no Docker
make check         # full CI-parity suite (ruby needs Docker) — see TESTING.md
```

---

## Known local-only sharp edges

- **amd64 emulation** — the image bakes amd64-only binaries (node x64 tarball, mysql .deb),
  so on Apple Silicon the build/run emulates amd64 (slower). This is expected.
- First `make local-init` can take ~15 min (cold build). Subsequent rebuilds are much
  faster thanks to the caching above.
