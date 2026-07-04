# ECR repo cutover: `idseq-web` → `seqtoid-web` (CZID-76)

## Why

`bin/build-docker` / `bin/push-docker` historically pushed the image to the legacy ECR repo **`idseq-web`**,
while the GitOps / Argo CD values reference **`czid-<env>/seqtoid-web`**
(`cypherid-web-infra/deploy/argocd/values/seqtoid-web/<env>.yaml`). Left unreconciled, a promoted
`sha-<commit>` tag pointed Argo CD at a repo nothing was pushed to, so the deploy could not resolve an image.

## The rule we followed

**Never rename an existing object.** We do **not** rename the live `idseq-web` ECR repo (it keeps its history
and any external consumers). Instead we introduce `seqtoid-web` as the **go-forward** name and **dual-push**
the *same* image to both repos during the transition, then drop the legacy name once every consumer has moved.

## What changed

- `bin/build-docker` and `bin/push-docker` now build/tag/push every name in the space-separated
  **`ECR_REPO_NAMES`** env var. Default: `"idseq-web seqtoid-web"` (dual-push). Same image content ⇒ the
  `sha-<commit>`, `branch-<name>`, and (on `main`) `latest` tags exist identically under both repo names.
- The chart default `image.repository` is now `seqtoid-web` (per-env GitOps values already point at
  `czid-<env>/seqtoid-web`, so this only affects standalone `helm template`/lint).

## Consumers and their state

| Consumer | Repo it references | State after this change |
|---|---|---|
| Argo CD / GitOps per-env values (`cypherid-web-infra`) | `czid-<env>/seqtoid-web` | ✅ resolves — dual-push publishes `seqtoid-web` |
| Helm chart default (`deploy/charts/seqtoid-web/values.yaml`) | `seqtoid-web` | ✅ go-forward |
| Legacy ECS deploy (`bin/deploy_automation/_global_vars.sh`, `bin/manual_deploy_scripts/czecs*.json`) | `idseq-web` | ✅ still resolves — legacy name kept, dual-push publishes it too |

## Prerequisite (ops)

The **`seqtoid-web` ECR repo must exist** in each account before the first dual-push (create it alongside the
existing `idseq-web`; both live in the same registry so the existing `docker login` covers both). The
account-scoped `czid-<env>/seqtoid-web` repos referenced by the GitOps values must likewise exist per env.

## Completing the cutover (later, separate PR)

Once every consumer references `seqtoid-web` and the `seqtoid-web` repo is confirmed populated across envs:

1. Repoint the legacy ECS path — `ECR_REPOSITORY_NAME` in `bin/deploy_automation/_global_vars.sh` and the
   image refs in `bin/manual_deploy_scripts/czecs*.json` — to `seqtoid-web`.
2. Drop `idseq-web` from `ECR_REPO_NAMES` in `bin/build-docker` / `bin/push-docker` (single-push go-forward).
3. Leave the `idseq-web` repo in place (frozen) or apply an ECR lifecycle policy — do not delete/rename it
   while any historical tag may still be referenced.
