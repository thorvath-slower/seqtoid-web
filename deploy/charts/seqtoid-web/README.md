# seqtoid-web Helm chart

Blue/green delivery of the seqtoid-web Rails app on EKS via **Argo Rollouts** (CZID-323; EKS cutover epic #319).
Consumed by the Argo CD Applications in `cypherid-web-infra/deploy/argocd/` (multi-source: this chart + per-env values).

## What it deploys
- **web `Rollout`** (blue/green) + active/preview Services + ALB `Ingress` (AWS LB Controller) → active.
- **5 worker Deployments** — resque ×4 + shoryuken (mirror the `czecs-*` task defs).
- **pre-sync migrate `Job`** — `rails db:migrate:with_data` (replaces the ECS run-task migrate).
- **`AnalysisTemplate`** — pre-promotion smoke gate: curl `/health_check` on the preview Service.
- **`ServiceAccount`** — IRSA (`eks.amazonaws.com/role-arn`).

## First-cut decisions (please review)
- **Secrets: Chamber kept** — the image entrypoint runs `chamber exec idseq-<env>-web`; the pod's IRSA role grants
  Secrets Manager access. External Secrets Operator is the later enhancement (CZID-325).
- **DB: MySQL 8, no Postgres** (CZID-320) — the app is already `mysql2`.
- **Logging: stdout** (`RAILS_LOG_TO_STDOUT=yes`) — K8s-native; drops the ECS awslogs driver.
- **Smoke gate: Job-based** (`/health_check`) — Prometheus-backed metrics are Bucket B (CZID-326).

## Values
Defaults in `values.yaml`; per-env overrides in
`cypherid-web-infra/deploy/argocd/values/seqtoid-web/{dev,staging,prod}.yaml` (image, IRSA roleArn, blue/green
gates [prod = manual], ingress host/cert). Render + validate locally:
`helm template seqtoid-web . -f <values>.yaml | kubeconform -ignore-missing-schemas -strict`.

## Status
First cut — covers #323 (Rollout/Services), #324 (workers/migrate), #326 (smoke gate) + the IRSA/logging part of
#325. NOT yet wired to live infra (needs P0 bootstrap #321 + the Argo Application repoURLs pointed at the fork).
