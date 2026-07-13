{{/*
Chart name / fullname. fullname = <project>-<environment>-seqtoid-node-backend
(e.g. czid-dev-seqtoid-node-backend) to mirror the seqtoid-web chart's
<project>-<env>-<name> convention and the RUNBOOK's ROLLOUT/NS naming.
*/}}
{{- define "seqtoid-node-backend.name" -}}
seqtoid-node-backend
{{- end -}}

{{- define "seqtoid-node-backend.fullname" -}}
{{- printf "%s-%s-%s" .Values.project .Values.environment (include "seqtoid-node-backend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Node runtime env. The Node config reads RAILS_ENV || ENVIRONMENT (see
deploy/k8s/node-backend-dev.yaml), so we set both. dev->development,
prod->production, else passthrough — same derivation as the web chart.
*/}}
{{- define "seqtoid-node-backend.railsEnv" -}}
{{- if eq .Values.environment "dev" -}}
development
{{- else if eq .Values.environment "prod" -}}
production
{{- else -}}
{{- .Values.environment -}}
{{- end -}}
{{- end -}}

{{/* ServiceAccount name. */}}
{{- define "seqtoid-node-backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "seqtoid-node-backend.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "seqtoid-node-backend.labels" -}}
app.kubernetes.io/name: {{ include "seqtoid-node-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: seqtoid
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
seqtoid.io/environment: {{ .Values.environment }}
{{- end -}}

{{/* API selector labels (Rollout injects rollouts-pod-template-hash on top). */}}
{{- define "seqtoid-node-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "seqtoid-node-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end -}}

{{/*
Shared pod env (api + worker). Mirrors deploy/k8s/node-backend-dev.yaml's
ConfigMap: RAILS_ENV + ENVIRONMENT (the Node config reads either), PORT,
AWS_REGION/AWS_DEFAULT_REGION, plus any extraEnv. Config from SSM and secrets
from Secrets Manager are fetched by the app's AwsModule at runtime (IRSA role),
or synced via external-secrets into secrets.externalSecrets.secretName and
envFrom'd — so individual secret values are NOT enumerated here.
*/}}
{{- define "seqtoid-node-backend.commonEnv" -}}
- name: RAILS_ENV
  value: {{ include "seqtoid-node-backend.railsEnv" . | quote }}
- name: ENVIRONMENT
  value: {{ .Values.environment | quote }}
- name: PORT
  value: {{ .Values.containerPort | quote }}
- name: AWS_REGION
  value: {{ .Values.aws.region | quote }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.aws.region | quote }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
envFrom block: only present when external-secrets is wired. Keeps a single
source of truth for both api + worker.
*/}}
{{- define "seqtoid-node-backend.envFrom" -}}
{{- if and .Values.secrets.externalSecrets.enabled .Values.secrets.externalSecrets.secretName }}
envFrom:
  - secretRef:
      name: {{ .Values.secrets.externalSecrets.secretName | quote }}
{{- end }}
{{- end -}}
