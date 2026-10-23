<!--
SPDX-FileCopyrightText: The OpenArtifact Authors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# openartifact

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/openartifact)](https://artifacthub.io/packages/helm/openartifact/openartifact)

Helm chart for [OpenArtifact](https://github.com/openartifact/openartifact), the
free-as-in-freedom artifact repository manager (Maven, npm, PyPI, Docker/OCI, Helm,
Debian, RPM, Go, Cargo, NuGet, RubyGems, Conda, Conan and more).

Requires Kubernetes 1.29+ and PostgreSQL. The full option reference with comments is
in [`values.yaml`](values.yaml); values are validated by
[`values.schema.json`](values.schema.json).

## Install

```sh
# OCI (recommended)
helm install openartifact oci://ghcr.io/openartifact/charts/openartifact \
  --namespace openartifact --create-namespace -f my-values.yaml

# Classic repository
helm repo add openartifact https://openartifact.github.io/helm-charts
helm install openartifact openartifact/openartifact \
  --namespace openartifact --create-namespace -f my-values.yaml
```

## Database

Pick one:

- **External PostgreSQL**: set `database.external.host`, `.name`, `.user` and either
  `.existingSecret` (recommended) or `.password`. `database.sslMode` defaults to `require`.
- **CloudNativePG**: with the [CloudNativePG operator](https://cloudnative-pg.io)
  installed, set `cnpg.enabled=true`. The chart creates a `Cluster` named
  `<release>-openartifact-db` and wires the generated `-app` credentials. Backups,
  replicas and PostgreSQL parameters go into `cnpg.instances` / `cnpg.extraSpec`.

Schema migrations run at startup under a Postgres advisory lock
(`config.migrateOnStart`), so several replicas can start concurrently. The server
waits up to `database.connectTimeout` (default `60s`) for the database at startup;
`database.waitForDatabase=false` makes it fail at once.

## Upgrading to 0.4.0 (OpenArtifact 0.7.0)

- Migrations `041`, `051`, `052` and `053` are additive; a rolling upgrade from 0.6.0 is
  fine, no `Recreate` needed.
- The `scanners`, `telemetry.otlp`, `blobDeletion`, `tiering`, `dockerUploads` and `tmp`
  values are new. Unset values pass nothing, so the server defaults apply and telemetry
  and runtime scanner install stay off.
- `trivy` / `grype` scans now use a background-downloaded database in the scanner cache
  (several GB, first download after start). The chart mounts that cache as an `emptyDir`;
  see [Vulnerability scanners](#vulnerability-scanners). Scanner processes no longer inherit
  the server's environment, only `PATH`, `HOME`, proxy/CA and `TRIVY_*` / `GRYPE_*` variables.
- Deleted blob bytes are removed after `blobDeletion.grace` (server default `24h`), so
  storage usage falls a day after a delete.
- See the
  [upgrade notes](https://github.com/openartifact/openartifact/blob/main/docs/getting-started/upgrading.md#070).

## Upgrading to 0.3.0 (OpenArtifact 0.6.0)

- Old and new replicas must not run side by side: migration `025` renames
  `organizations` to `projects`. With more than one replica, or object storage (which
  defaults to `RollingUpdate`), set `updateStrategy: {type: Recreate}` for this upgrade
  or scale to 0 first.
- Migration `030` creates the `pg_trgm` extension. The bundled CloudNativePG cluster
  allows it (the app user owns the database); on external PostgreSQL the user must
  own the database or the extension must exist already.
- `config.legacyApiKeyEnabled` now defaults to `false`; set it to `true` if you still use
  `secrets.apiKey`.
- See the
  [upgrade notes](https://github.com/openartifact/openartifact/blob/main/docs/getting-started/upgrading.md#060).

## Upgrading to 0.2.0 (OpenArtifact 0.5.0)

- The image no longer has a shell: the `wait-for-database` init container is gone (the
  server waits itself) and `helm test` uses a pinned `curlimages/curl` image.
- Old and new replicas must not run side by side (migrations `018`, `019`, `022`).
  With more than one replica set `updateStrategy: {type: Recreate}` for this upgrade,
  or scale to 0 first. See the
  [upgrade notes](https://github.com/openartifact/openartifact/blob/main/docs/getting-started/upgrading.md#050).

## Blob storage

| `storage.type` | Required values | Credentials (`storage.credentials.*` or `existingSecret`) |
|---|---|---|
| `filesystem` (default) | `persistence.*` | – |
| `s3`, `garage`, `seaweedfs` | `storage.bucket`, `storage.region`, `storage.endpoint` for non-AWS | `accessKey`/`secretKey`, or the AWS credential chain (IRSA, Pod Identity) |
| `gcs` | `storage.gcs.bucket` | `gcsHmacKey`/`gcsHmacSecret` |
| `azure` | `storage.azure.accountName`, `.containerName` | `azureAccountKey` |
| `oci` | `storage.endpoint` | `ociUsername`/`ociPassword` |

`storage.credentials.existingSecret` is loaded with `envFrom`; its keys are the
environment variable names (`STORAGE_ACCESS_KEY`, `STORAGE_SECRET_KEY`, …).

## High availability

More than one replica (`replicaCount > 1` or `autoscaling.enabled`) needs storage every
pod can mount: an object storage backend, or `persistence.accessModes: [ReadWriteMany]`.
The chart refuses to render otherwise. With a single `ReadWriteOnce` volume the
Deployment uses the `Recreate` strategy, so upgrades have a short downtime.

## Vulnerability scanners

The default `osv` scanner needs nothing. For `trivy` / `grype` either use an image built
with the `SCANNERS` build argument, or set `scanners.trivy.install=auto` /
`scanners.grype.install=auto`: the server then downloads the release it pins (versions are
not set by the chart) from `github.com` (or `scanners.downloadBaseUrl`, an https mirror
serving GitHub's release paths), verifies its checksum and runs it from
`<scanners.cache.path>/bin`.

| Value | Meaning |
|---|---|
| `scanners.cache.path` / `.sizeLimit` / `.persistence.*` | Cache of databases and installed binaries. `emptyDir` by default (re-downloaded after a restart); a PVC avoids that. Must be writable by uid 10001 (`fsGroup` already is) and not `noexec`. |
| `scanners.offline` | Never download databases; fill the cache yourself. |
| `scanners.updateInterval` | Database refresh, `0` or `>= 1h` (server default `6h`). |
| `scanners.trivy.dbRepository`, `.javaDbRepository`, `scanners.grype.dbUrl` | Database mirrors for air-gapped or proxied clusters. |
| `scanners.trivy.path`, `scanners.grype.path` | Use a binary you provide (e.g. via `extraInitContainers` + `extraVolumes`). |

With several replicas each pod downloads its own copy unless the cache is a shared
`ReadWriteMany` volume. Egress needed: `ghcr.io` and `mirror.gcr.io` (Trivy databases),
`grype.anchore.io` (Grype), and with `install=auto` `github.com` plus
`release-assets.githubusercontent.com`.

## OpenTelemetry

`telemetry.otlp.enabled=true` exports traces over OTLP (`endpoint`, `protocol`
`grpc|http`, `insecure`, `serviceName`, `sampleRatio`); `telemetry.otlp.metrics=true`
also pushes the Prometheus registry. Collector credentials never go in values: put
`OTEL_EXPORTER_OTLP_HEADERS` (`k=v,k2=v2`, percent-encoded values) in a Secret and set
`telemetry.otlp.headersExistingSecret` (and `headersSecretKey` if the key differs). Any other
`OTEL_*` variable goes through `env` / `extraEnv`. `/metrics` is unaffected.

## Retention, tiering and scratch space

- `blobDeletion.*` (grace, sweep interval, batch), `tiering.*` (mover switch, interval,
  batch, concurrency, bandwidth cap, read-back verification) and `backups.leaseTtl` map to
  the matching `OPENARTIFACT_*` variables; leave them empty to keep the server defaults.
  Tiers and policies themselves are managed in the admin UI/API. While the mover is on
  (the server default), `database.maxOpenConns` must be 0 or at least 4; the chart refuses
  smaller values unless `tiering.enabled=false`.
- The root filesystem is read-only; `/tmp` is an `emptyDir` (`tmp.sizeLimit`, `tmp.medium`)
  where uploads and proxy downloads are spooled. Docker/OCI blob uploads are staged under
  `/tmp/openartifact/docker-uploads` by default; set `dockerUploads.dir` to give them a
  dedicated `emptyDir` (`dockerUploads.sizeLimit`) or PVC (`dockerUploads.persistence.*`),
  and `dockerUploads.ttl` for the idle-session lifetime.
- `config.projectsSelfCreate` lets any authenticated user create projects.

## Web UI as an installable app (PWA)

Serve OpenArtifact over HTTPS (or `localhost`) so browsers offer to install it. Your
ingress must pass `/sw.js` and `/manifest.webmanifest` through with their
`Cache-Control: no-cache` header intact (no response caching or header overrides on them).
No chart values are needed.

## Secrets

The chart-managed Secret holds `AUTH_HMAC_KEY` (OIDC/SAML state) and
`OPENARTIFACT_SECRET_KEY` (encrypts stored credentials at rest). Both are generated
on first install and reused on upgrade. The Secret is kept on `helm uninstall`
(`secrets.keepOnUninstall`); **back it up**, because losing `OPENARTIFACT_SECRET_KEY`
makes stored credentials unreadable.

Generation relies on Helm's `lookup`, which does not run under `helm template`. For
GitOps tools that render with `helm template` (Argo CD), create the Secret yourself and
set `secrets.existingSecret`. It is loaded with `envFrom`, so it can also carry
`DB_PASSWORD`, `API_KEY`, `METRICS_AUTH_TOKEN`, `AI_API_KEY`,
`OPENARTIFACT_SAML_SP_CERT`/`_KEY` and any other sensitive setting.

```sh
kubectl create secret generic openartifact \
  --from-literal=AUTH_HMAC_KEY="$(openssl rand -hex 32)" \
  --from-literal=OPENARTIFACT_SECRET_KEY="$(openssl rand -hex 32)"
```

## Exposure

- `ingress.*` creates an `networking.k8s.io/v1` Ingress. Artifact uploads are often
  large: raise the controller's body size limit (e.g.
  `nginx.ingress.kubernetes.io/proxy-body-size: "0"`).
- `httpRoute.*` creates a Gateway API `HTTPRoute`.
- Set `baseUrl` to the public URL and `config.trustedProxies` to the CIDR of your
  ingress controller so client IPs and SSO callbacks are correct.

## Other settings

- Any OpenArtifact environment variable can be set with `env` (plain) or
  `secrets.extra` (sensitive), e.g. `env.AI_ENABLED: "true"`, `env.MCP_ENABLED: "true"`.
- `metrics.enabled` protects `/metrics` with `METRICS_AUTH_TOKEN`;
  `metrics.serviceMonitor.enabled` creates a Prometheus Operator `ServiceMonitor` that
  authenticates with it.
- `gpg.enabled` mounts the signing key from `gpg.existingSecret` (`private.key`,
  optional `passphrase`).
- `networkPolicy.enabled` limits ingress to the HTTP port from `networkPolicy.from`.
  `networkPolicy.egress.enabled` also restricts egress: it then allows DNS, the
  CloudNativePG cluster, the OTLP collector (`egress.otlp`, when telemetry is on) and scanner
  downloads (`egress.scanners`, unless `scanners.offline`), plus `egress.extra`. Standard
  NetworkPolicies cannot match host names, so an empty `to` means any destination on that
  port; add the external database, object storage, upstream proxies, webhook targets and
  SSO providers to `egress.extra`.
- Webhook payload formats and license metadata need no chart settings.

## Probes

| Probe | Endpoint | Meaning |
|---|---|---|
| startup / liveness | `/health` | Process is serving (always 200, reports degraded components) |
| readiness | `/ready` | Database and object storage are reachable |

`helm test <release>` calls `/ready` through the Service.
