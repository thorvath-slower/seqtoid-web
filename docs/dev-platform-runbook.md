# seqtoid-web — Dev Platform Runbook

**Audience:** any engineer (junior or new to the project) who needs to understand, deploy, watch, or troubleshoot the **dev** environment of the seqtoid-web app running on Kubernetes (EKS).

**One-sentence summary:** you `git push` to the `seqtoid-web` `main` branch, and a few minutes later your change is live in dev — **automatically**, with no manual steps. This doc explains what happens in between, how to watch it, and what to do when something breaks.

> **Scope:** this is the **dev** pipeline. **Staging and prod are NOT automated** — their deploys are a separate, human-gated path. Nothing in this runbook auto-touches staging or prod. `dev.seqtoid.org` (the public URL) still points at the *old* ECS setup; the new EKS app runs alongside it internally until a future planned DNS cutover.

---

## 1. The mental model (read this first)

Three AWS acronyms that sound alike but are completely different — internalize these:

| Thing | What it is | Analogy |
|---|---|---|
| **ECR** — Elastic Container **Registry** | Where built Docker **images are stored** | A private Docker Hub |
| **ECS** — Elastic Container **Service** | The **old** way we ran containers (being retired) | The old server |
| **EKS** — Elastic Kubernetes **Service** | The **new** way we run containers (Kubernetes) | The new server |

We are migrating **ECS → EKS** (where containers *run*). **ECR stays** — it's the image store both use. When you hear "we're moving to EKS," images still live in ECR.

**The four moving parts of the pipeline:**

```
  ┌───────────────┐    push image    ┌──────────┐   pulls image   ┌───────────────┐
  │  seqtoid-web  │ ───────────────► │   ECR    │ ◄────────────── │  EKS cluster  │
  │  (the app,    │                  │ (images) │                 │ czid-dev-eks  │
  │   Ruby/Rails) │                  └──────────┘                 │  (Kubernetes) │
  └──────┬────────┘                                               └──────▲────────┘
         │ merge to main triggers a build,                               │ Argo CD watches
         │ then bumps the image tag in ...                               │ Git and syncs
         ▼                                                               │
  ┌────────────────────┐   Argo CD reads the desired image tag from here │
  │ cypherid-web-infra │ ───────────────────────────────────────────────┘
  │ (Terraform +       │
  │  Argo/Helm values) │
  └────────────────────┘
```

- **`seqtoid-web`** (GitHub: `thorvath-slower/seqtoid-web`) — the Rails application code + the Helm chart that describes how it runs on Kubernetes (`deploy/charts/seqtoid-web`).
- **`cypherid-web-infra`** (GitHub: `thorvath-slower/cypherid-web-infra`) — Terraform (AWS infrastructure) **and** the Argo CD config + per-environment values that say *which image tag* each environment runs (`deploy/argocd/values/seqtoid-web/dev.yaml`).
- **ECR** — stores the built images (`491013321714.dkr.ecr.us-west-2.amazonaws.com/idseq-web` and `.../seqtoid-web`; we push both names during a naming transition).
- **EKS** (`czid-dev-eks`) — the Kubernetes cluster. **Argo CD** runs inside it, watches Git, and makes the cluster match what Git says ("GitOps").

**GitOps in one sentence:** Git is the source of truth. You don't run `kubectl apply` to deploy — you change a file in Git, and Argo CD makes the cluster match it.

---

## 2. The golden path: ship a code change to dev

This is 95% of what you'll do. **All of it is automatic after step 3.**

1. Branch off `seqtoid-web` `main`, make your change, open a PR.
2. Get it reviewed; CI must be green (RSpec on MySQL 8, RuboCop, Brakeman, etc.).
3. **Merge the PR to `main`.** That's the last thing you do by hand.

Then, automatically:

4. **Build** (`.github/workflows/build-docker-image.yml`) — builds the Docker image (using a layer cache, so ~2–4 min for a typical change), scans it with Trivy, signs it with cosign, and pushes it to ECR tagged `sha-<first8ofcommit>`.
5. **Tag advance** (`.github/workflows/gitops-advance-dev.yml`) — after a green build, this opens a tiny PR in `cypherid-web-infra` that changes `dev.yaml`'s `image.tag` to your new `sha-…`, **waits for that PR's checks, and auto-merges it**. No human.
6. **Deploy** — Argo CD sees `dev.yaml` changed on `main`, and rolls the new image onto the cluster (a blue/green rollout via Argo Rollouts).

**How you know it worked:** see §4. Typical total time from merge to live: **~5–8 minutes**.

> If any check on the auto-tag PR fails, the auto-merge **stops** and leaves that PR open for a human — it is never force-merged.

---

## 3. Accessing the cluster (do this once per session)

You need this to watch or debug anything on EKS. **Read the gotcha — it bites everyone.**

```bash
# 1. Log in to AWS SSO (opens a browser)
aws sso login --profile idseq-dev

# 2. Point kubectl at the dev cluster
aws eks update-kubeconfig --name czid-dev-eks --region us-west-2 --profile idseq-dev

# 3. ALWAYS export this in your shell — the kubeconfig's token command does NOT
#    include --profile, so without it kubectl uses the wrong/empty credentials.
export AWS_PROFILE=idseq-dev

# 4. Verify
kubectl get pods -n seqtoid-dev
```

> ### ⚠️ The #1 gotcha: `Credentials were refreshed, but the refreshed credentials are still expired`
> This almost always means your shell has **stale AWS credentials exported as environment variables** (`AWS_ACCESS_KEY_ID`, `AWS_SESSION_TOKEN`, …) left over from something else. They **override** `--profile`, so nothing works. Fix:
> ```bash
> unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
> export AWS_PROFILE=idseq-dev
> aws sts get-caller-identity   # should print account 491013321714
> ```

**Key facts for the dev cluster:**
- AWS account: `491013321714`  ·  Region: `us-west-2`  ·  SSO profile: `idseq-dev`
- EKS cluster: `czid-dev-eks`
- App namespace: `seqtoid-dev`  ·  Argo CD namespace: `argocd`
- Argo application name: `seqtoid-web-dev`

---

## 4. Watching / verifying a deploy

```bash
# Argo application status — you want "Synced / Healthy"
kubectl get application seqtoid-web-dev -n argocd \
  -o jsonpath='{.status.sync.status} / {.status.health.status}{"\n"}'

# The workloads (web pods should be N/N Ready)
kubectl get rollout,pods,svc -n seqtoid-dev

# Which image tag is actually running right now?
kubectl get pods -n seqtoid-dev -l app.kubernetes.io/component=web \
  -o jsonpath='{.items[*].spec.containers[0].image}{"\n"}'

# Is the app actually serving HTTP? (run a throwaway pod inside the cluster)
kubectl run httpcheck -n seqtoid-dev --image=busybox:1.36 --restart=Never -i --rm --command -- \
  wget -qO- http://czid-dev-seqtoid-web-active.seqtoid-dev.svc.cluster.local/health_check
# Expected output: success
```

**What "done" looks like:** Argo `Synced / Healthy`, the web pods `1/1 Running` on the new `sha-…` tag, and `/health_check` returns `success`.

**Reading app logs** (the boot log dumps which config it loaded — secrets are redacted as `[REDACTED]`):
```bash
POD=$(kubectl get pods -n seqtoid-dev -l app.kubernetes.io/component=web -o name | head -1)
kubectl logs "$POD" -n seqtoid-dev --tail=100
```

---

## 5. What runs in the cluster (component reference)

When Argo deploys, it creates these in namespace `seqtoid-dev`:

| Component | What it is |
|---|---|
| **Rollout** `czid-dev-seqtoid-web` | The web server pods (Rails/Puma), managed by **Argo Rollouts** for blue/green deploys. Has an `active` and `preview` Service. |
| **Deployments** `…-resque`, `…-resque-scheduler`, `…-resque-pipeline-monitor`, `…-resque-result-monitor`, `…-shoryuken` | Background job workers (Resque/Redis + Shoryuken/SQS). |
| **ServiceAccount** `seqtoid-web` | The pod identity. Carries an AWS IAM role annotation (**IRSA**) so pods get AWS permissions (read secrets, S3, etc.) **without any keys**. |
| **PreSync hook Job** `…-migrate` | Runs `rails db:migrate` **before** the app deploys. Argo waits for it to succeed. |
| **PreSync hook Job** `…-taxon-load` | Loads the taxon-lineage reference data + builds the OpenSearch index, **before** the app deploys. Idempotent — skips if already loaded/indexed. |

**Two Kubernetes concepts a junior should know here:**
- **IRSA** (IAM Roles for Service Accounts): the pod assumes an AWS role via its ServiceAccount — that's how it reads secrets from AWS SSM (via a tool called **chamber**) with no hardcoded credentials.
- **PreSync hook**: a Kubernetes Job Argo runs *before* it deploys the app, and waits for it to pass. We use it for DB migrations and reference-data loading.

**Where the app gets its config/secrets:** the container entrypoint runs `chamber exec idseq-dev-web -- …`, which pulls secrets from AWS SSM Parameter Store at boot and injects them as environment variables. You don't manage `.env` files for dev EKS.

---

## 6. Common manual operations

### Build a specific branch on demand (without merging to main)
```bash
gh workflow run build-docker-image.yml \
  --repo thorvath-slower/seqtoid-web --ref <your-branch> -f environment=dev
# Watch it:
gh run watch <run-id> --repo thorvath-slower/seqtoid-web
```
The image lands in ECR tagged `sha-<first8>` and `branch-<name>`.

### Roll dev to a specific image tag manually
Edit `deploy/argocd/values/seqtoid-web/dev.yaml` in `cypherid-web-infra`, set `image.tag: sha-XXXXXXXX`, and merge to `main`. Argo picks it up. (Normally the pipeline does this for you.)

### Force Argo to re-check / re-sync now
```bash
kubectl -n argocd annotate application seqtoid-web-dev argocd.argoproj.io/refresh=hard --overwrite
```

### Check migration status (read-only, one-off pod)
```bash
kubectl run migstatus -n seqtoid-dev --restart=Never -i --rm \
  --image=491013321714.dkr.ecr.us-west-2.amazonaws.com/seqtoid-web:sha-<TAG> \
  --overrides='{"spec":{"serviceAccountName":"seqtoid-web","containers":[{"name":"migstatus","image":"491013321714.dkr.ecr.us-west-2.amazonaws.com/seqtoid-web:sha-<TAG>","args":["rails","db:migrate:status"],"env":[{"name":"RAILS_ENV","value":"development"},{"name":"ENVIRONMENT","value":"dev"},{"name":"AWS_REGION","value":"us-west-2"}]}]}}'
```
> One-off pods that need the app image must set `serviceAccountName: seqtoid-web` (for IRSA/secrets) and env `RAILS_ENV=development ENVIRONMENT=dev AWS_REGION=us-west-2`. The entrypoint is `chamber exec … -- bundle exec "$@"`, so pass `args` like `["rails","db:migrate:status"]` — if you need a shell, use `["bash","-c","… bundle exec rails …"]` (bare `rails` won't be on PATH inside a plain shell).

### Terraform / AWS infra changes
Infra lives in `cypherid-web-infra/terraform`. Applies are run through `bin/tf-linux` (runs Terraform in a linux container). **Plan first, always** — only apply when the plan reads `X to add, 0 to change, 0 to destroy`. **Never** blind-apply the `dev/web` stack (it has drift); target specific resources with `-target`. **Dev only** — do not apply staging/prod.

---

## 7. Troubleshooting (real issues we've hit)

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl`: *credentials still expired* | Stale AWS env vars shadowing the profile | `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` then `export AWS_PROFILE=idseq-dev` (see §3 gotcha) |
| Pod `CrashLoopBackOff`, log says **`exec format error`** | The image is amd64-only but the pod landed on an **arm64 (Graviton)** node | The chart pins pods to amd64 (`nodeSelector: kubernetes.io/arch: amd64`). If you see this, a pod is missing the nodeSelector — check the chart. |
| Migration Job fails: *MySQL version (5.7.x) not supported* | Stale `StrongMigrations.target_version` | It's env-driven now (`STRONG_MIGRATIONS_TARGET_VERSION`, default `8.0`). The dev DB is MySQL 8. |
| App times out at boot on **Redis / DB / OpenSearch** | The EKS **node** security group isn't allowed into that service's SG | Node SG (`czid-dev-eks-node-sg`) needs ingress on the backing service (Redis 6379 / Aurora 3306 / OpenSearch 443). This is codified in Terraform (`dev/web`). |
| `taxon-load` hook takes ~an hour | It's building the OpenSearch index from scratch | Normal only on a **first** load. It's guarded now — on later deploys it **skips** in ~15s if the index is in sync. If it rebuilds every time, the guard isn't working — check the rake task. |
| Migration Job stuck: *table already exists* | A previous migrate Job was interrupted mid-run (partial migration) | Reconcile the DB: mark the migration recorded / add the missing index, or drop the empty half-created table and re-run. Ask a senior — this touches the shared dev DB. |
| Argo `OutOfSync` and won't converge | A sync operation failed (check the failing resource) | `kubectl get application seqtoid-web-dev -n argocd -o jsonpath='{.status.operationState.message}'` and read the per-resource results. |

**Where to look first for a failed auto-deploy:**
1. GitHub Actions → the `Build and Push Docker Images` run (did the build/scan pass?).
2. GitHub Actions → the `gitops-advance-dev` run (did the tag PR open + auto-merge?).
3. Argo (`kubectl get application seqtoid-web-dev -n argocd`) → did it sync? Which resource failed?

---

## 8. The build cache (why builds are fast)

`bin/build-docker` uses **BuildKit (`docker buildx`) with an ECR registry cache in `mode=max`**. The image is multi-stage; `mode=max` caches **every** stage's layers (including the expensive builder stage: `npm ci`, webpack, `bundle install`) to a dedicated `idseq-web:buildcache` tag in ECR. The next build restores those layers and only rebuilds what changed:
- **Backend (Ruby) change** → rebuilds just the code layer (~2–4 min).
- **Frontend change** → rebuilds just the webpack layer.
- **`Gemfile` change** → rebuilds just `bundle install`.

Measured: a full cache hit took **~70s** vs **~600s** cold (~9×). You don't do anything to use it — it's automatic in CI. (A future optional enhancement, ticketed, is to only *write* the cache on a weekend cron and read-only during the week.)

---

## 9. Safety rules (do not violate)

- **Dev automation is dev-only.** The auto-build/auto-merge/auto-deploy pipeline touches **only** `dev.yaml`. Staging and prod tag advances are a **separate, human-gated** path. Never wire staging/prod into the auto-merge.
- **`dev.seqtoid.org` and the ECS app are untouched** by any of this. The EKS app runs internally (ClusterIP, no public ingress) until a deliberate, tested DNS cutover.
- **Terraform:** plan before apply; only apply changes that are `0 to change, 0 to destroy` unless you *understand* the change; never blind-apply `dev/web`; dev only.
- **The shared dev DB:** migrations run automatically, but manual DB surgery (dropping tables, editing `schema_migrations`) is a senior-review action — it affects the same database the old ECS app also uses.

---

## 10. Glossary

- **GitOps** — Git is the source of truth for what runs; a controller (Argo CD) makes the cluster match Git.
- **Argo CD** — the controller in the cluster that watches Git and syncs the desired state.
- **Argo Rollouts** — does progressive (blue/green) deploys of the web pods (active vs preview).
- **Helm chart** — a templated set of Kubernetes manifests (`seqtoid-web/deploy/charts/seqtoid-web`) that describes how the app runs.
- **PreSync hook** — a Job Argo runs *before* deploying (migrations, data load).
- **IRSA** — IAM Roles for Service Accounts; how pods get AWS permissions with no keys.
- **chamber** — the tool the entrypoint uses to pull secrets from AWS SSM at boot.
- **ECR / ECS / EKS** — see §1. Registry / old runtime / new runtime. ECR is a keeper.
- **strangler** — the migration pattern: run the new system (EKS) alongside the old (ECS) and shift traffic over gradually.

---

*Questions this doc doesn't answer? Check the accomplishments/handoff docs in the workspace root, or the tickets in `czid/platform-overhaul` (#476–#485 cover pipeline follow-ups).*
