# Artifact management + image promotion policy (CZID-464)

How a seqtoid-web container image goes from "built" to "running in prod", and the rules that keep the
**byte-identical, tested artifact** — not a rebuild, not a floating tag — as the thing that promotes.

## Registry model

| Registry | Role | Populated by |
|---|---|---|
| **GHCR** (`ghcr.io/<owner>/seqtoid-web`) | **source-of-record** for our built images | build → GHCR publish (CZID-392) |
| **ECR** (`<acct>/czid-<env>/seqtoid-web`, per env) | **deploy mirror**, in-VPC pull for the cluster | build push (CZID-76 go-forward name) |

Images are **immutable-tagged**: `sha-<commit>` + a SemVer `vX.Y.Z_…` (CZID-392) + the content digest
`sha256:…`. The **digest is the promotion unit** — tags are for humans, the digest is what advances.

## The pipeline (`promote-image.yml` → `promote-to-env.yml`)

```
resolve-and-test (resolve digest from GHCR → Trivy scan → boot/health smoke test)
   → promote-dev      (ungated)
     → promote-staging (Environment: staging — required-reviewer approval)
       → promote-prod  (Environment: prod — required-reviewer approval)
```

- **Test gate before promotable.** `resolve-and-test` resolves the exact digest for the requested
  source, re-scans it (Trivy, hard-fail HIGH/CRITICAL) and runs a container smoke/health test. A
  failure blocks the whole promotion — nothing untested advances.
- **Digest-based promotion.** Each tier writes `image.digest` (the immutable `sha256`) plus the
  readable `image.tag` (`sha-<commit>`) into that env's GitOps values in the infra repo, via a PR.
  The same digest flows dev → staging → prod, so every tier runs the artifact that passed the test.
- **Manual / environment approval.** Real promotion to **staging** and **prod** is gated on the
  matching GitHub Environment's protection rules (required reviewers, CZID-81). **Prod is never
  auto-promoted** — the `promote-prod` job cannot start until a reviewer approves. `dev` is ungated
  for a fast inner loop (and `gitops-advance-dev.yml` still auto-advances dev on a green main build).
- **Promotion is recorded.** Each tier uploads a `promotion-<env>.json` provenance record (env,
  digest, tag, reason, actor, run URL, timestamp) and opens a titled GitOps PR whose merge is the
  durable, auditable record of what was promoted where.

## How to promote

Run the **promote-image** workflow (Actions → Run workflow):
- `source` — a `sha-<commit>` tag, a `vX.Y.Z_…` version tag, or a raw commit sha.
- `promote_to` — `dev` | `staging` | `prod` (each lower tier is done first).
- `deployment_reason` — free text (scheduled / hotfix / issue id).

## Chart adoption note (image.digest)

`promote-to-env.yml` writes `image.digest`. The chart today renders `repository:tag`; to make the
cluster pull **by digest** (fully immutable), the chart's image ref should prefer
`repository@{{ .image.digest }}` when `image.digest` is set (small `_helpers.tpl` change in the app
chart + infra values — tracked separately, does not block this pipeline; until then the digest-pinned
`sha-<commit>` tag is what deploys and the digest is recorded for audit/correlation).

## Prerequisites for a real run (ops — flagged, not blocking authoring)

- **`GITOPS_TOKEN`** (CZID-74): scoped write to the infra repo + PR create (already used by
  `gitops-advance-dev.yml`).
- **GitHub Environments** `staging` / `prod` with **required-reviewer** protection rules (CZID-81) —
  this is what makes the approval gates real. Until they exist the `environment:` reference is a
  no-op and promotion would proceed ungated, so create them before enabling staging/prod promotion.
- The go-forward **`seqtoid-web` ECR repos** per env (CZID-76) so the mirror side resolves.

## Relationship to the other CD workflows

| Workflow | Purpose |
|---|---|
| `build-docker-image.yml` (#304/#392) | build + scan + push + publish to GHCR — produces the artifact |
| `gitops-advance-dev.yml` (#444) | auto-advance **dev** on a green main build (fast loop) |
| **`promote-image.yml` (#464)** | **deliberate, tested, digest-pinned promotion across all tiers with approval gates** |
| `deploy-promote.yml` (#101) | the older ref-based deploy chain (rebuild-per-tier); superseded for artifact promotion by the digest flow |
