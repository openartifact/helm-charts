{{/*
SPDX-FileCopyrightText: The OpenArtifact Authors
SPDX-License-Identifier: AGPL-3.0-or-later
*/}}

{{- define "openartifact.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openartifact.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "openartifact.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "openartifact.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openartifact.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "openartifact.labels" -}}
helm.sh/chart: {{ include "openartifact.chart" . }}
{{ include "openartifact.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: openartifact
{{- end }}

{{- define "openartifact.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openartifact.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "openartifact.image" -}}
{{- $repo := printf "%s/%s" .Values.image.registry .Values.image.repository | trimPrefix "/" }}
{{- if .Values.image.digest }}
{{- printf "%s@%s" $repo .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" $repo (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/* Name of the Secret holding application secrets (envFrom). */}}
{{- define "openartifact.secretName" -}}
{{- default (include "openartifact.fullname" .) .Values.secrets.existingSecret }}
{{- end }}

{{- /* Secret holding the bootstrap admin password (and token) files. */}}
{{- define "openartifact.bootstrapSecretName" -}}
{{- default (printf "%s-bootstrap" (include "openartifact.fullname" .)) .Values.bootstrap.existingSecret }}
{{- end }}

{{- define "openartifact.bootstrapEnabled" -}}
{{- if or .Values.bootstrap.existingSecret .Values.bootstrap.createSecret }}true{{- end }}
{{- end }}

{{- define "openartifact.storageSecretName" -}}
{{- default (printf "%s-storage" (include "openartifact.fullname" .)) .Values.storage.credentials.existingSecret }}
{{- end }}

{{- define "openartifact.storageCredentials" -}}
{{- $c := .Values.storage.credentials }}
{{- $m := dict }}
{{- with $c.accessKey }}{{ $_ := set $m "STORAGE_ACCESS_KEY" . }}{{ end }}
{{- with $c.secretKey }}{{ $_ := set $m "STORAGE_SECRET_KEY" . }}{{ end }}
{{- with $c.gcsHmacKey }}{{ $_ := set $m "OPENARTIFACT_GCS_HMAC_KEY" . }}{{ end }}
{{- with $c.gcsHmacSecret }}{{ $_ := set $m "OPENARTIFACT_GCS_HMAC_SECRET" . }}{{ end }}
{{- with $c.azureAccountKey }}{{ $_ := set $m "OPENARTIFACT_AZURE_ACCOUNT_KEY" . }}{{ end }}
{{- with $c.ociUsername }}{{ $_ := set $m "STORAGE_OCI_USERNAME" . }}{{ end }}
{{- with $c.ociPassword }}{{ $_ := set $m "STORAGE_OCI_PASSWORD" . }}{{ end }}
{{- toYaml $m }}
{{- end }}

{{- define "openartifact.cnpgClusterName" -}}
{{- printf "%s-db" (include "openartifact.fullname" .) | trunc 50 | trimSuffix "-" }}
{{- end }}

{{- define "openartifact.dbHost" -}}
{{- if .Values.cnpg.enabled }}
{{- printf "%s-rw" (include "openartifact.cnpgClusterName" .) }}
{{- else }}
{{- required "database.external.host is required unless cnpg.enabled=true" .Values.database.external.host }}
{{- end }}
{{- end }}

{{- define "openartifact.dbPort" -}}
{{- if .Values.cnpg.enabled }}5432{{ else }}{{ .Values.database.external.port }}{{ end }}
{{- end }}

{{- define "openartifact.filesystemStorage" -}}
{{- if or (eq .Values.storage.type "filesystem") (eq .Values.storage.type "") }}true{{ end }}
{{- end }}

{{/* True when a mounted volume (blobs, backups, scanner cache or docker uploads) cannot be shared between pods. */}}
{{- define "openartifact.singleWriterVolume" -}}
{{- if and (include "openartifact.filesystemStorage" .) .Values.persistence.enabled (not (has "ReadWriteMany" .Values.persistence.accessModes)) }}true
{{- else if and .Values.backups.persistence.enabled (not (has "ReadWriteMany" .Values.backups.persistence.accessModes)) }}true
{{- else if and .Values.scanners.cache.persistence.enabled (not (has "ReadWriteMany" .Values.scanners.cache.persistence.accessModes)) }}true
{{- else if and .Values.dockerUploads.dir .Values.dockerUploads.persistence.enabled (not (has "ReadWriteMany" .Values.dockerUploads.persistence.accessModes)) }}true
{{- end }}
{{- end }}

{{- define "openartifact.validate" -}}
{{- $multi := or .Values.autoscaling.enabled (gt (int .Values.replicaCount) 1) }}
{{- if and $multi (include "openartifact.filesystemStorage" .) (not .Values.persistence.enabled) }}
{{- fail "filesystem storage with more than one replica needs persistence.enabled=true and a ReadWriteMany volume, or an object storage backend" }}
{{- end }}
{{- if and $multi (include "openartifact.singleWriterVolume" .) }}
{{- fail "more than one replica needs ReadWriteMany in the accessModes of every enabled persistence volume (persistence, backups.persistence, scanners.cache.persistence, dockerUploads.persistence), or an object storage backend (and emptyDir for the others)" }}
{{- end }}
{{- if and .Values.secrets.existingSecret .Values.database.external.password (not .Values.cnpg.enabled) }}
{{- fail "database.external.password is stored in the chart-managed Secret; with secrets.existingSecret put DB_PASSWORD there or use database.external.existingSecret" }}
{{- end }}
{{- if and .Values.bootstrap.existingSecret .Values.bootstrap.createSecret }}
{{- fail "bootstrap.existingSecret and bootstrap.createSecret are mutually exclusive" }}
{{- end }}
{{- if and .Values.bootstrap.adminToken.enabled (not (include "openartifact.bootstrapEnabled" .)) }}
{{- fail "bootstrap.adminToken.enabled requires bootstrap.existingSecret (with an admin-token key) or bootstrap.createSecret=true" }}
{{- end }}
{{- if and .Values.bootstrap.adminToken.ttl (not .Values.bootstrap.adminToken.enabled) }}
{{- fail "bootstrap.adminToken.ttl requires bootstrap.adminToken.enabled=true" }}
{{- end }}
{{- if and .Values.gpg.enabled (not .Values.gpg.existingSecret) }}
{{- fail "gpg.enabled requires gpg.existingSecret" }}
{{- end }}
{{- if and (kindIs "bool" .Values.tiering.enabled) .Values.tiering.enabled (gt (int .Values.database.maxOpenConns) 0) (lt (int .Values.database.maxOpenConns) 4) }}
{{- fail "database.maxOpenConns must be 0 or at least 4 while tiering.enabled=true (the tier mover pins connections)" }}
{{- end }}
{{- if and (not (kindIs "bool" .Values.tiering.enabled)) (gt (int .Values.database.maxOpenConns) 0) (lt (int .Values.database.maxOpenConns) 4) }}
{{- fail "database.maxOpenConns must be 0 or at least 4 unless tiering.enabled=false (the tier mover is on by default and pins connections)" }}
{{- end }}
{{- if and .Values.dockerUploads.persistence.enabled (not .Values.dockerUploads.dir) }}
{{- fail "dockerUploads.persistence.enabled requires dockerUploads.dir" }}
{{- end }}
{{- if and .Values.telemetry.otlp.headersExistingSecret (not .Values.telemetry.otlp.enabled) }}
{{- fail "telemetry.otlp.headersExistingSecret requires telemetry.otlp.enabled=true" }}
{{- end }}
{{- if and .Values.metrics.serviceMonitor.enabled (not .Values.metrics.enabled) }}
{{- fail "metrics.serviceMonitor.enabled requires metrics.enabled=true" }}
{{- end }}
{{- end }}
