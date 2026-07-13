# seqtoid-web Platform Guide

**How this system works, how to use it, and the rules that keep it safe.**

This is the single entry point. It ties together the branching model, CI gates, the
automated dev deploy chain, the self-heal, preview sandboxes, and the fork/upstream
governance. Deep-dives live in the per-topic docs linked throughout; this page is the map.

- Branching flow detail: [`branching.md`](branching.md)
- Dev deploy runbook (watch/troubleshoot): [`dev-platform-runbook.md`](dev-platform-runbook.md)
- Deploy/promotion mechanics: [`DEPLOY-METHODS.md`](DEPLOY-METHODS.md), [`DEPLOY-PROMOTION.md`](DEPLOY-PROMOTION.md), [`ARTIFACT-PROMOTION.md`](ARTIFACT-PROMOTION.md)
- Local dev: [`LOCAL-DEV.md`](LOCAL-DEV.md) · Testing: [`TESTING.md`](TESTING.md) · PR scope/naming: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)

---

## 1. TL;DR

1. Branch off **`integration`** (`cat-NNN-slug`). Make a small, single-concern change.
2. `make ci-local` -> green **before** you push. CI is the final gate, not your dev loop.
3. Open a PR into `integration`. Label it **`preview`** to get an isolated per-PR sandbox
   (`pr-N.dev.seqtoid.org`) you can upload to and run real pipelines in.
4. Green checks + 1 review -> merge to `integration`.
5. Every night at **09:00 UTC (1 AM PST / 2 AM PDT)** the green state of `integration` is
   auto-promoted to **`main`**, which auto-builds and deploys to shared **dev**. Urgent fixes
   don't wait -- trigger the same promotion off-cycle by hand.
6. `main` -> **staging** -> **prod** is a separate, human-gated, digest-pinned chain.

```
feature ---PR---> integration ---nightly 09:00 UTC---> main ---auto---> dev (shared)
(off integration)  (dev trunk +   (or hotfix dispatch)  (known-good)  dev.seqtoid.org
                    preview sandboxes)                                  |
                                                          main --gated--> staging --gated--> prod
```

---

## 2. The repos (who owns what)

| Repo (`thorvath-slower/…`) | Role |
|---|---|
| **seqtoid-web** | The Rails app + its Helm chart (`deploy/charts/seqtoid-web`). You work here. |
| **cypherid-web-infra** | GitOps: Terraform + Argo CD values. Holds the per-env **image tag** dev runs (`deploy/argocd/values/seqtoid-web/dev.yaml`). |
| **seqtoid-workflows** | WDL pipelines / index generation. |
| **cypherid-workflow-infra**, **seqtoid-ssot-infra**, **seqtoid-ci-workflows** | Workflow infra, shared state, reusable CI. |

**Fork lineage:** `thorvath-slower/*` is **our** working fork (git remote `origin`). Upstreams:
`IT-Academic-Research-Services/*` (remote `itars`, the **live UCSF** repos) and `jsims-slower/*`
(remote `jsims`). See [§10 Fork & upstream governance](#10-fork--upstream-governance).

**AWS / cluster (dev):** account `idseq-dev` (`491013321714`), region `us-west-2`, cluster
`czid-dev-eks-v2`, namespace `seqtoid-dev`. ECR: `491013321714.dkr.ecr.us-west-2.amazonaws.com/seqtoid-web`
(also `/idseq-web` during the naming transition).

---

## 3. Branch rules (enforced protection)

| Branch | Who writes to it | Protection |
|---|---|---|
| `cat-NNN-slug` (feature) | you | none -- your workspace |
| **`integration`** | feature PRs | required checks (below) + **1 review**; no force-push, no delete. The active dev trunk; hosts preview sandboxes. Does **not** deploy anywhere persistent. |
| **`main`** | **only** the `integration -> main` promotion | required checks + **0 reviews** (every commit was already reviewed on its feature PR) + **enforce_admins**; no direct pushes, no feature PRs, no force-push, no delete. The known-good trunk; auto-deploys to dev. |

**Required status checks** (both `integration` and `main`): `Javascript`,
`Ruby Test (MySQL 8)` shards 1-4, `Collate coverage + regression gate`. Additionally the PR
runs `rubocop`/`brakeman` via **reviewdog** (reports on changed lines only), and the **build**
runs the Trivy **image** scan gate ([§6](#6-the-trivy-image-scan-gate)).

> Admin-bypass merges (`gh pr merge --admin`) exist for the maintainer to land promotion PRs and
> expedited fixes. They bypass the review/1-review requirement, **not** good judgement -- only use
> after checks are green (or a failure is understood), and never to skip a real gate.

---

## 4. The dev inner loop (what you actually do)

1. **Branch off `integration`:** `git switch -c cat-NNN-slug origin/integration`. You build on the
   latest in-flight state, so your PR is a clean increment. (Naming + one-concern rules: [CONTRIBUTING](../CONTRIBUTING.md).)
2. **Validate locally FIRST:** `make ci-local` -> green in Docker before you push
   ([§7](#7-local-validation)). CI is the final gate, not your dev loop.
3. **Open a small PR into `integration`.** Label it **`preview`** to get a sandbox.
4. **Use your preview sandbox** at `pr-N.dev.seqtoid.org`: its **own** app + DB schema + user +
   SSM + S3 prefix, so you can upload samples and run pipelines end-to-end without touching anyone
   else's data. It dispatches to the **shared dev** Batch/Step-Functions backend and loads results
   back into **your** sandbox DB only. ([§8](#8-preview-sandboxes))
5. **Merge to `integration`** once green + reviewed. The sandbox tears down when the PR closes or
   the `preview` label is removed.

---

## 5. Promotion & the automated dev deploy chain

### `integration` -> `main` (nightly, automated)

`.github/workflows/promote-integration-to-main.yml` runs on **`cron: "0 9 * * *"`** =
**09:00 UTC = 1 AM PST / 2 AM PDT**. It opens (or reuses) an `integration -> main` PR and enables
auto-merge; branch protection on `main` is what actually gates it, so the roll-up only lands when
`integration`'s HEAD is green.

Why 09:00 UTC: it's overnight Pacific (nobody mid-push, so the roll-up captures a stable state) and
one hour **after** the nightly test suite (`0 8 * * *`) so the promoted HEAD is freshly tested and
the two never overlap. GitHub cron is UTC-only (no DST), so literal "midnight PST" (08:00 UTC) would
collide with the test suite -- hence 09:00. (Cadence history: was weekly `0 15 * * 1`; changed to
nightly, platform-overhaul #680.)

### Hotfix (expedited promotion)

Urgent dev fixes don't wait for the cron. The fix **still flows through `integration`** (preview
sandbox + normal checks + review), then a person triggers the **same** workflow off-cycle via
**`workflow_dispatch`**. One promotion path, two triggers (`schedule` + `workflow_dispatch`) -- no
divergent route, no magic commit-message suffix.

### `main` -> dev (automatic GitOps)

A green `main` push:

1. **Build** (`build-docker-image.yml`) -- builds the image (BuildKit ECR layer cache, ~70s-few min),
   runs the **Trivy image scan gate** ([§6](#6-the-trivy-image-scan-gate)), signs (cosign), pushes to
   ECR as `sha-<first8ofcommit>`.
2. **GitOps advance** (`gitops-advance-dev.yml`) -- bumps the dev image tag in
   `cypherid-web-infra` (`.../values/seqtoid-web/dev.yaml`, `image.tag: sha-<8>`).
3. **Argo CD** (running in `czid-dev-eks-v2`) sees the Git change and rolls it out (blue/green with a
   smoke gate) into namespace `seqtoid-dev`.

**If the build fails, gitops is skipped and dev stays on the last good image** -- that's the gate
working, not a silent drop. See [§9 Troubleshooting](#9-troubleshooting).

### `main` -> staging -> prod (gated)

Separate, digest-pinned chain -- the exact tested artifact is walked forward, each tier behind a
GitHub Environment approval. Prod is never deployed directly. See
[`DEPLOY-PROMOTION.md`](DEPLOY-PROMOTION.md) / [`ARTIFACT-PROMOTION.md`](ARTIFACT-PROMOTION.md).
**Everything staging/prod is human-gated; nothing in the dev chain auto-touches them.**

---

## 6. The Trivy image-scan gate

The `build-dev-docker-image` job scans the built image with Trivy:
`severity: HIGH,CRITICAL`, **`ignore-unfixed: true`**, `trivyignores: .trivyignore`. So it fails the
build on any **fixable** HIGH/CRITICAL that is **not** in the `.trivyignore` baseline.

`.trivyignore` is a **gate-on-new baseline**: it accepts the CURRENT known findings so the (already
far-more-secure) image ships, and fails only when a **new** fixable CVE appears. Each entry is a
bare `CVE-…` id; the header documents `pkg -> fixed version` for the remediation backlog (#474).

> ### ⚠️ Rule: confirm against the IMAGE before removing a baseline entry
> Trivy scans the **image filesystem** (every gemspec under the Ruby install + `node_modules`/lock),
> not just `Gemfile.lock`. **Ruby default gems** (`uri`, `zlib`, `erb`, `net-imap`) persist in the
> image even when you pin them forward in the `Gemfile` -- the pin fixes the *runtime* (bundler
> activates the patched version) but the vulnerable default-gem **file** remains, and Trivy still
> finds it. Removing such a CVE from the baseline while it's still in the image makes the gate treat
> it as *new* -> **build fails -> dev deploys blocked** (this happened: #319 removed uri/zlib, hotfix
> #325 re-added them). **Before deleting any `.trivyignore` entry, confirm the CVE is gone from the
> image:**
> ```
> trivy image --severity HIGH,CRITICAL --ignorefile /dev/null \
>   491013321714.dkr.ecr.us-west-2.amazonaws.com/seqtoid-web:sha-<8>
> ```
> Default-gem CVEs need a **Dockerfile** fix (update/remove the default gemspec), not a `Gemfile` pin.

---

## 7. Local validation

Run the exact CI steps locally before pushing:

```
make ci-local          # full local CI (docker-compose.ci.yml -> ruby:3.3.6, amd64)
make check             # local parity for the security/lint reusable checks
```

`docker-compose.ci.yml` runs `bin/ci-test` in `ruby:3.3.6` on **`platform: linux/amd64`** (emulated
under qemu on Apple Silicon -- slower, but it mirrors the amd64 GitHub runners faithfully). It sets
`bundle config path vendor/bundle` (a cache volume), installs deps, loads the MySQL 8 schema, and
runs RSpec (parallel shards). A scoped run for one file:

```
docker compose -f docker-compose.ci.yml run --rm test bash -lc \
  'bundle config path vendor/bundle; RAILS_ENV=test bundle exec rake db:drop db:create db:schema:load; \
   bundle exec rspec spec/models/your_spec.rb'
```

Notes: the app **hard-requires MySQL 8** (ROW_NUMBER). npm has quirks (legacy-peer-deps, engine
pins) -- see [`LOCAL-DEV.md`](LOCAL-DEV.md). Some specs shell out to the `aws` CLI; a missing `aws`
binary in the local container is a known-harness gap, not a real failure (passes on CI).

---

## 8. Preview sandboxes

Label a `seqtoid-web` PR **`preview`** and a per-PR system spins up `seqtoid-pr-N`: its own schema,
DB user, SSM params, S3 prefix, and host `pr-N.dev.seqtoid.org` -- fully isolated, but it dispatches
to the **shared dev** Batch/SFN backend. Upload + run real pipelines without touching shared dev or
anyone else's sandbox. Removing the label or closing the PR tears it down (namespaces are reaped).
`main -> dev` is untouched by previews.

---

## 9. Troubleshooting

**"My merged change isn't on dev."** Check the chain in order:
```
gh run list --branch main --limit 8            # did the build succeed?
# build 'Build and Push Docker Images' = failure? -> gitops is skipped, dev stays on last good image.
gh run list --workflow=gitops-advance-dev.yml  # did gitops advance the tag?
kubectl get pods -n seqtoid-dev -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | grep -o 'sha-[0-9a-f]*' | sort -u
```
- **Build failed at "Scan image (Trivy)"** -> a fixable HIGH/CRIT not in `.trivyignore` (often a
  default-gem CVE -- see [§6](#6-the-trivy-image-scan-gate)). Fix the dep or (correctly) baseline it.
- **Build failed at job setup / "Service Unavailable"** -> transient GitHub-infra hiccup. The
  **self-heal** ([§below](#self-heal-auto-rerun)) auto-re-runs it; only intervene if it exhausts retries.

### Self-heal (auto-rerun)

`.github/workflows/auto-rerun-transient.yml` chains off the CI/CD workflows via
`workflow_run(completed)`. On a FAILED run under the retry cap (`run_attempt < 3`), it classifies the
failed-job logs transient-vs-real and **auto-re-runs only transient ones** (runner Service-Unavailable/
deprovision, registry/network 5xx, docker-daemon-not-ready, empty setup log) after a 30s backoff.
Real failures (rspec/tsc/rubocop/brakeman/trivy CVE/npm ERR) always win and are left failed. Live in
all active `thorvath-slower` repos (platform-overhaul #678).

---

## 10. Fork & upstream governance

- **All our work goes to `thorvath-slower/*`** (remote `origin`) through the flow above.
- **Never push to the `main` of `IT-Academic-Research-Services` (live UCSF) or `jsims-slower`.**
  Pull upstream changes DOWN into our fork -- `git cherry-pick -x <sha>` (preserves upstream
  authorship + records the source), reconcile any diverged files/specs, then PR into `integration`.
- When adapting a pulled change to our diverged code, **fix tests properly** -- convert them to assert
  the new behavior or remove tests for removed functionality; do **not** leave `xit`/skipped zombies.
- The retired `modernization` snapshot branch is no longer used. The end-state is to run this same
  model directly on the IT-ARS repos.

---

## 11. Ticketing

Tickets live in self-hosted **Forgejo** (`localhost:3300`, project `czid/platform-overhaul`), driven
by `~/forgejo/fj.py`. Forgejo closes are mirrored to **Jira** (`SMP-*`) via `~/forgejo/jira_sync.py`
as **comment + In Progress only** -- Jira issues are closed by a human at standup, never by
automation. Leave a closing comment (what/PR/validation) on a Forgejo ticket **before** setting it
Done. New tickets are appended to `TICKETS-OPENED-LOG.md`.

---

## 12. Quick cookbook

| I want to… | Do this |
|---|---|
| Ship a change to dev | Branch off `integration` -> `make ci-local` -> PR (label `preview`) -> merge. It reaches dev on the nightly roll-up (or a hotfix dispatch). |
| Get a change to dev **now** | After it's merged to `integration`, run the `Promote integration -> main` workflow via `workflow_dispatch`. |
| See what's on dev | `kubectl get pods -n seqtoid-dev … | grep sha-` (image tag = `sha-<first8 of the main commit>`). |
| Watch a rollout | `gh run list --branch main` (build) -> `gitops-advance-dev` -> `kubectl -n seqtoid-dev get pods -w`. |
| Run one spec like CI | `docker compose -f docker-compose.ci.yml run --rm test …` ([§7](#7-local-validation)). |
| Pull an upstream fix | `git cherry-pick -x <sha>` from `itars`/`jsims`, reconcile, PR into `integration`. |
| Remove a `.trivyignore` entry | First `trivy image` the built image to confirm the CVE is actually gone ([§6](#6-the-trivy-image-scan-gate)). |
