{{- define "seqtoid-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "seqtoid-web.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "seqtoid-web.labels" -}}
app.kubernetes.io/name: {{ include "seqtoid-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "seqtoid-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "seqtoid-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "seqtoid-web.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "seqtoid-web.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "seqtoid-web.commonEnv" -}}
- name: RAILS_ENV
  value: {{ .Values.environment | quote }}
- name: ENVIRONMENT
  value: {{ .Values.environment | quote }}
- name: RAILS_LOG_TO_STDOUT
  value: "yes"
- name: AWS_REGION
  value: {{ .Values.awsRegion | quote }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.awsRegion | quote }}
{{- range $k, $v := .Values.extraEnv }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- end -}}
