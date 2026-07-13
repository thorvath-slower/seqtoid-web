# seqtoid-node-backend Helm chart

The NestJS/Node backend (the strangler slice, epic #454) packaged for EKS via
Argo CD + Argo Rollouts. This is the Helm/Rollout form of the plain manifests in
[`rewrite-node-nestjs/deploy/k8s/node-backend-dev.yaml`](../../k8s/node-backend-dev.yaml)
— same two workloads, but delivered as a blue/green Rollout with a smoke gate,
mirroring the [`seqtoid-web`](../seqtoid-web) chart (#323-327).

> **GATED / not applied.** Standing up the EKS cluster, filling the real ECR
> repo / IRSA role ARN / DNS / cert / subnets, and the live `kubectl apply` are
> cluster-blocked (dev EKS not yet stood up). This chart is authored + validated
> (`helm lint` + `helm template` + `kubeconform`) only. See ticket #455.

## What it ships

| Workload | Kind | Command | Notes |
|---|---|---|---|
| api | Argo `Rollout` (blueGreen) | `node dist/main.js` | active/preview Services; smoke AnalysisRun gates promotion |
| worker | `Deployment` (Recreate) | `node dist/jobs/worker.js` | BullMQ workers + SFN-notifications SQS consumer (port of resque×4 + shoryuken) |
| smoke | `AnalysisTemplate` | curl preview `/health_check` | HTTP-200 gate; abort → active untouched |
| — | `ServiceAccount` | — | IRSA role annotation (SSM/SecretsManager/S3/SFN/SQS/STS) |
| — | `Ingress` (ALB) | — | **separate hostname** from Rails; `internal` in dev |
| — | `HorizontalPodAutoscaler` | — | off by default; per-env at cutover |

## Strangler invariants (dev-only, account 491013321714)

- Runs **alongside** Rails on its **own hostname**; shares the same Aurora / S3 /
  SWIPE / SQS. No schema changes, no new pipeline infra. Turn Node off → Rails
  unaffected.
- The worker must use its **own dev SFN-notifications SQS queue** (or dev Rails'
  Shoryuken is paused) so the two monitors don't race — set
  `SFN_NOTIFICATIONS_QUEUE_ARN` via `extraEnv`.
- `DEMO_MODE` stays unset (real auth + real ES384 token minting).
- staging/prod values render for CI but are **not deployed** until the
  full-cutover ticket (#457).

## Config + secrets

- Non-secret config: SSM (`/idseq-<env>-web/*`, `/idseq/<env>/web/*`), fetched by
  the app's `AwsModule` at runtime given the IRSA role's SSM read.
- Secrets (ES384 signing key `<env>/czid-services-private-key`, DB password):
  fetched by the app from Secrets Manager, **or** synced into a k8s Secret via
  external-secrets and `envFrom`'d — set `secrets.externalSecrets.enabled=true`
  + `secretName`.

## Values

Env overrides live in
`cypherid-web-infra/deploy/argocd/values/seqtoid-node-backend/<env>.yaml` and
layer over `values.yaml`. Key knobs: `image.repository/tag`,
`serviceAccount.roleArn`, `blueGreen.autoPromotionEnabled` (dev/staging true,
prod false), `ingress.host/scheme/certificateArn`, `extraEnv` (queue ARN).

## Validate locally

```sh
helm lint deploy/charts/seqtoid-node-backend
helm template nb deploy/charts/seqtoid-node-backend | \
  kubeconform -strict -summary -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
