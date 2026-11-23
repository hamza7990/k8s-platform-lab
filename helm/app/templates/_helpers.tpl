{{/* Name used for every object and for the label selectors. */}}
{{- define "app.name" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}

{{/* Labels put on every object. */}}
{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Labels a Service or Deployment uses to find the pods. Must never change. */}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
