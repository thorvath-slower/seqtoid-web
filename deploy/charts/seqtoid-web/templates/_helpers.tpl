{{/*
Chart name / fullname. fullname = <project>-<environment>-seqtoid-web
(e.g. czid-dev-seqtoid-web) to match the ECS family + the RUNBOOK's
ROLLOUT=czid-prod-seqtoid-web / NS=czid-<env> convention.
*/}}
{{- define "seqtoid-web.name" -}}
seqtoid-web
{{- end -}}

{{- define "seqtoid-web.fullname" -}}
{{- printf "%s-%s-%s" .Values.project .Values.environment (include "seqtoid-web.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Rails env derived from the logical environment, unless explicitly set. */}}
{{- define "seqtoid-web.railsEnv" -}}
{{- if .Values.railsEnv -}}
{{- .Values.railsEnv -}}
{{- else if eq .Values.environment "dev" -}}
development
{{- else if eq .Values.environment "prod" -}}
production
{{- else -}}
{{- .Values.environment -}}
{{- end -}}
{{- end -}}

{{/* Chamber service name (idseq-<env>-web) unless overridden. */}}
{{- define "seqtoid-web.chamberService" -}}
{{- default (printf "idseq-%s-web" .Values.environment) .Values.secrets.chamber.service -}}
{{- end -}}

{{/* Samples bucket: explicit override, else the czecs pattern, else empty. */}}
{{- define "seqtoid-web.samplesBucket" -}}
{{- if .Values.aws.samplesBucketName -}}
{{- .Values.aws.samplesBucketName -}}
{{- else if .Values.aws.accountId -}}
{{- printf "idseq-samples-%s-%s" .Values.environment (.Values.aws.accountId | toString) -}}
{{- end -}}
{{- end -}}

{{/* ServiceAccount name. */}}
{{- define "seqtoid-web.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "seqtoid-web.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "seqtoid-web.labels" -}}
app.kubernetes.io/name: {{ include "seqtoid-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: seqtoid
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
seqtoid.io/environment: {{ .Values.environment }}
{{- end -}}

{{/* Web selector labels (Rollout injects rollouts-pod-template-hash on top). */}}
{{- define "seqtoid-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "seqtoid-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: web
{{- end -}}

{{/*
Shared pod env (web + workers + migrate). Mirrors the czecs task-def env:
RAILS_ENV, ENVIRONMENT, RAILS_LOG_TO_STDOUT (K8s captures stdout -> no awslogs),
AWS_REGION/AWS_DEFAULT_REGION, plus any extraEnv. Secrets come from Chamber at
runtime (image ENTRYPOINT), so they are not enumerated here.
*/}}
{{- define "seqtoid-web.commonEnv" -}}
- name: RAILS_ENV
  value: {{ include "seqtoid-web.railsEnv" . | quote }}
- name: ENVIRONMENT
  value: {{ .Values.environment | quote }}
- name: RAILS_LOG_TO_STDOUT
  value: "yes"
- name: AWS_REGION
  value: {{ .Values.aws.region | quote }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.aws.region | quote }}
{{- with .Values.aws.accountId }}
- name: AWS_ACCOUNT_ID
  value: {{ . | quote }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}
