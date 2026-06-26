# SeqtoID — Local Demo Runbook

How to download and launch the SeqtoID demo locally (landing page → log in → browse seeded data).

---

## 1. Repositories required

| Repo | Why | Needed for the demo? |
|---|---|---|
| **`thorvath-slower/seqtoid-web`** | the application (Rails + React, MySQL 8, Rails-native GraphQL) | **Yes — this is the only repo you need** |
| `thorvath-slower/seqtoid-graphql-federation-server` | the old GraphQL federation server | **No — decommissioned.** The federation collapse removed it; the app no longer depends on it |
| `thorvath-slower/seqtoid-workflows` | bioinformatics pipelines | **No** — the demo is the app UI + seeded data, not live pipeline runs |
| `thorvath-slower/cypherid-web-infra` | AWS/Terraform infrastructure | **No** — only for cloud deployment, not the local demo |

**Bottom line: the demo is now single-repo.** Everything it needs (web app, MySQL 8, Redis, OpenSearch) comes
up from `seqtoid-web`'s own `docker-compose.yml` (the DB/Redis/OpenSearch are standard images, pulled
automatically — not separate checkouts).

## 2. Branch required

| Branch | What it is |
|---|---|
| **`mysql8-demo-on-main`** | **the demo branch** — production `main` **+** the local demo layer (seed data, a dev-login shortcut, and offline auth so you don't need a live Auth0). **Use this branch.** |
| `main` | the production-hardened branch — **no** seed data, **no** dev-login, **no** offline auth. Not directly demo-able locally (it expects real Auth0 + a real database). |

The demo branch differs from `main` by exactly 5 files (the demo affordances); the application itself is identical.

## 3. Prerequisites

- **Docker** + **Docker Compose v2** (with BuildKit).
- **git** with access to the private `thorvath-slower` org.
- ~8 GB free disk and ~6 GB RAM available to Docker.
- **Apple Silicon (M-series) note:** the images are `linux/amd64` and run under emulation (the compose pins the
  platform). It works, but the **image build (~10 min) and the frontend asset build (~7 min) are slow** the first
  time. Intel/amd64 hosts are faster.

### Ubuntu 24.04 (x86_64) — Docker install + platform notes

On Ubuntu 24.04 the images run **natively** (`linux/amd64`), so there is **no emulation** — builds are noticeably
faster than the Apple-Silicon figures above. The launch steps in section 4 apply unchanged.

Install Docker Engine + Compose v2 from Docker's official apt repository:

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# run docker without sudo (then log out/in, or run `newgrp docker`)
sudo usermod -aG docker "$USER" && newgrp docker

docker --version && docker compose version   # verify
```

- **OpenSearch:** this compose runs it `discovery.type=single-node` with bootstrap checks skipped and `memlock`
  ulimits set, so the usual Linux `vm.max_map_count` tuning is **not** required.
- Everything else (the `.env`, the `node_modules` override, and the build/seed/asset/restart flow) is identical to
  section 4.

## 4. Launch steps

```bash
# 1. Clone the demo branch (requires thorvath-slower access)
git clone --branch mysql8-demo-on-main --single-branch \
  git@github.com:thorvath-slower/seqtoid-web.git seqtoid-demo
cd seqtoid-demo

# 2. Minimal env (dummy AWS values so the image name + config resolve; nothing hits AWS)
cat > .env <<'ENV'
AWS_ACCOUNT_ID=test
AWS_REGION=us-west-2
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AUTH_TOKEN_SECRET=GYbvZ9/uHy75wWWK4BO3jZGJ0noacv7GbTJI96wZgWQ=
ENV

# 3. Keep the image's node_modules from being shadowed by the source mount
#    (temporary — folded into the compose once the turnkey fix lands)
cat > docker-compose.override.yml <<'OVR'
services:
  web:
    volumes:
      - /app/node_modules
OVR

# 4. Build the web image (~10 min on Apple Silicon)
DOCKER_BUILDKIT=1 docker compose build web

# 5. Start the services (web, MySQL 8, Redis, OpenSearch)
docker compose up -d
sleep 20   # let MySQL 8 finish first-time init

# 6. Create + load + seed the database (creates the demo admin account)
docker compose exec -T web bash -lc \
  'cd /app && RAILS_ENV=development bundle exec rails db:create db:schema:load db:seed'

# 7. Build the frontend assets inside the running container (~7 min on Apple Silicon)
docker compose exec -T web bash -lc 'cd /app && npm run build-img'

# 8. Restart web so it serves the freshly built bundles
docker compose restart web
```

The offline signing key the app needs is already in the repo and mounted automatically by the compose file —
no manual key step.

## 5. Using the demo

- Open **http://localhost:3001** — the landing page renders (logo, hero images, Sign In).
- **Log in** (demo shortcut, no Auth0 needed): open
  **http://localhost:3001/direct_user_login?user_id=1** — this signs you in as the seeded admin
  (`czid-e2e@chanzuckerberg.com`).
- You can then browse the authenticated app: **My Data**, **Samples**, **Public**, etc., backed by the seeded data.

> The dev-login shortcut and seed data exist **only on the demo branch** — they are deliberately absent from
> production `main`.

## 6. Stop / clean up

```bash
docker compose down            # stop containers (keeps the built image)
docker compose down -v         # also remove volumes (DB data) for a clean re-seed
```

## 7. Notes / troubleshooting

- **Landing page returns 500 right after first boot:** the web container started before the asset bundles were
  built. Re-run step 7 (asset build) then step 8 (`docker compose restart web`).
- **`webpack: not found` during the asset build:** the `docker-compose.override.yml` from step 3 is missing —
  add it and recreate web (`docker compose up -d web`).
- **MySQL "Failed to initialize DD Storage Engine":** leftover data from an older MySQL version. Run
  `docker compose down -v` (and delete `docker_data/db` if present) for a clean MySQL 8 init.
- **First build is slow on Apple Silicon** — that's the amd64 emulation, not an error. Subsequent builds reuse the
  cache and are much faster.
