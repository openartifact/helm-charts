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

## Probes

| Probe | Endpoint | Meaning |
|---|---|---|
| startup / liveness | `/health` | Process is serving (always 200, reports degraded components) |
| readiness | `/ready` | Database and object storage are reachable |

`helm test <release>` calls `/ready` through the Service.
