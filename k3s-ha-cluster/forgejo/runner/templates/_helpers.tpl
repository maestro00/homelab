{{- define "forgejo-runner.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "forgejo-runner.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "forgejo-runner.name" .) | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end -}}

{{- define "forgejo-runner.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else if .Release.ServiceAccountName }}
{{- .Release.ServiceAccountName }}
{{- else }}
{{- printf "%s-%s" (include "forgejo-runner.fullname" .) "sa" }}
{{- end }}
{{- end -}}
