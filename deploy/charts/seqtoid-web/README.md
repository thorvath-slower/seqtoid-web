# seqtoid-web Helm chart

Runs **seqtoid-web on EKS** via **Argo CD + Argo Rollouts**, replacing the ECS/czecs
task-definition path. This is the crux artifact of the ECS→EKS blue/green cutover
(EKS-BLUEGREEN-CUTOVER-PLAN-2026-06-27.md; epic #319).

## What it renders

| Template | Replaces (ECS) | Notes |
|---|---|---|
| `rollout.yaml` | `czecs.json` (web service) | `kind: Rollout`, **blueGreen** strategy, active/preview Services |
| `services.yaml` | ALB target group | `<fullname>-active` (live) + `<fullname>-preview` (new color) |
| `workers.yaml` | `czecs-resque.json` ×4 + `czecs-shoryuken.json` | resque / scheduler / pipeline-monitor / result-monitor + shoryuken Deployments |
| `migrate-job.yaml` | `czecs-task-migrate.json` (run-task) | `rails db:migrate:with_data` as an Argo CD **PreSync hook** |
| `analysistemplate.yaml` | (new) | smoke Job — curls the preview color's `/health_check`; gates promotion |
| `ingress.yaml` | external ALB | AWS Load Balancer Controller → the **active** Service |
| `serviceaccount.yaml` | ECS web task role | **IRSA** (`eks.amazonaws.com/role-arn`) |
| `hpa.yaml` | ECS service autoscaling | targets the Rollout (prod only) |

## Delivery model

- The **chart** lives here (versions with the code). **Env values** live in
  `cypherid-web-infra/deploy/argocd/values/seqtoid-web/<env>.yaml` and are layered on
  via the Argo CD multi-source Application.
- **dev/staging**: `blueGreen.autoPromotionEnabled: true` — promote automatically once
  the smoke AnalysisRun passes. **prod**: `false` — the rollout pauses after smoke for a
  manual `kubectl argo rollouts promote`.
- **Secrets**: least-change path — the image ENTRYPOINT (`bin/entrypoint.sh`) runs
  `chamber exec idseq-<env>-web`, so the pod only needs the IRSA role with SSM read.
  (External Secrets Operator is a later swap — #325.)
- **DB**: MySQL 8 via **RDS reached from the pods** (the committed direction); no
  in-cluster DB. `deploy/postgres/` is the separate appliance adapter.
- **Logs**: `RAILS_LOG_TO_STDOUT=yes` → stdout (K8s-native); no `awslogs`.

## Local validation

```sh
helm lint deploy/charts/seqtoid-web
for env in dev staging prod; do
  helm template svc deploy/charts/seqtoid-web \
    -f ../cypherid-web-infra/deploy/argocd/values/seqtoid-web/$env.yaml \
    | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.30.0 -summary
done
```

The CI gate (cypherid-web-infra `argocd-ci.yml`, #327) additionally validates the
Argo `Rollout` / `AnalysisTemplate` CRDs against the schema catalog.

## Not yet wired (blocked on AWS applies — Phase 0/2)

Image account/DNS/cert/subnet values still carry `REPLACE_*` placeholders (filled with
the real applied infra), and the control-plane bootstrap (LBC IRSA, Argo CD install,
`root-app`) is #321. The GitOps image-tag advance that triggers a deploy is #444.
