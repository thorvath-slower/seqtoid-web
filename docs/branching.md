# Branching + promotion model

How code moves from a laptop to production, and what each branch means. This is the
*flow*; for PR shape/scope discipline see [`../CONTRIBUTING.md`](../CONTRIBUTING.md),
and for the deploy/promotion *mechanics* see [`DEPLOY-METHODS.md`](DEPLOY-METHODS.md),
[`DEPLOY-PROMOTION.md`](DEPLOY-PROMOTION.md), and [`ARTIFACT-PROMOTION.md`](ARTIFACT-PROMOTION.md).

> **TL;DR:** Branch off `main`. Open a small PR into `integration`. It spins up an
> isolated per-PR preview sandbox you can upload to and run pipelines in. When
> `integration` is promoted to `main`, `main` auto-deploys to the shared **dev**
> environment. `main` then promotes forward through **staging -> prod** on the gated
> chain. `main` is always the known-good trunk.

---

## The picture

```
  feature branch  --PR-->  integration  --promote-->  main  --auto-->  dev (shared)
  (cat-NNN-slug)      |                        (known-good trunk)          |
                      |                                                    |
                      v                                                    v
             per-PR PREVIEW sandbox                        main --gated--> staging --gated--> prod
             pr-N.dev.seqtoid.org                          (deploy-promote, digest-pinned)
             (own app + DB + S3;
              shared dev Batch/SFN backend)
```

- **`main` = known-good.** It is the only branch that auto-deploys to the shared
  **dev** environment (`dev.seqtoid.org`) via GitOps (`gitops-advance-dev.yml` ->
  Argo CD). Nothing else touches the dev pipeline.
- **`integration` = the staging branch for changes.** Feature PRs target it. It is
  reset to `main` and kept protected; it promotes *to* `main`, it does **not** deploy
  to dev.
- **feature branches** are where you work: `cat-NNN-short-slug` off `main`.

---

## The dev inner loop (what you actually do)

1. **Branch off `main`:** `git switch -c cat-NNN-short-slug origin/main`
   (naming + one-concern rules: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)).
2. **Validate locally first:** `make ci-local` -> green in Docker **before** you push.
   CI is the final gate, not your dev loop.
3. **Open a small PR into `integration`.** This triggers:
   - the required checks (`Javascript`, `Ruby Test (MySQL 8)` shards 1-4,
     `Collate coverage + regression gate`) + 1 review, and
   - a **per-PR preview build** (`build-pr-preview.yml`) that pushes an isolated
     image, which the preview sandbox deploys.
4. **Use your preview sandbox** at `pr-N.dev.seqtoid.org`: it has its **own** app, DB,
   and S3, so you can upload samples and run pipelines end-to-end without touching
   anyone else's data. It dispatches to the **shared dev** Batch/Step Functions
   backend and loads results back into **your** sandbox DB only.
5. **Merge to `integration`** once green + reviewed. The sandbox is torn down when the
   PR closes.

## Promotion (integration -> main -> dev -> staging -> prod)

- **`integration` -> `main`:** promote the reviewed, green `integration` state to
  `main` (a PR; `main` requires the same checks + a review). This is the gate that
  makes something "known-good".
- **`main` -> dev:** automatic. A green `main` build advances the dev image tag via
  GitOps and Argo rolls it out (blue/green with a smoke gate).
- **`main` -> staging -> prod:** the gated, digest-pinned promotion chain -- the exact
  tested artifact is walked forward, each tier behind a GitHub Environment approval.
  See [`DEPLOY-PROMOTION.md`](DEPLOY-PROMOTION.md) + [`ARTIFACT-PROMOTION.md`](ARTIFACT-PROMOTION.md).
  Prod is never deployed directly.

---

## Branch protection (enforced)

Both `main` and `integration` (on `thorvath-slower/seqtoid-web`) require:
- the full required status checks above,
- at least 1 approving review,
- no force-push, no deletion.

So nothing lands on either branch without green CI + a review.

---

## What is live vs coming

| Piece | Status |
|---|---|
| `main` -> dev auto-deploy (GitOps + Argo) | **Live** |
| `integration` branch + protection | **Live** |
| Per-PR preview **build** (`build-pr-preview.yml` + scoped ECR/role) | **Landing** (apply the infra, then enable the workflow) |
| Per-PR preview **sandboxes** (Argo ApplicationSet: app + DB + S3 per PR) | **Phase 2 (in progress)** |
| `main` -> staging -> prod promotion chain | **Defined**; staging/prod clusters being stood up |

Until the preview sandboxes land, feature PRs still target `integration` and validate
via `make ci-local` + CI; the isolated `pr-N.dev.seqtoid.org` environment arrives with
Phase 2.
