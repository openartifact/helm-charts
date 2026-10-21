<!--
SPDX-FileCopyrightText: The OpenArtifact Authors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# OpenArtifact Helm charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/openartifact)](https://artifacthub.io/packages/search?repo=openartifact)

Helm charts for [OpenArtifact](https://github.com/openartifact/openartifact).

| Chart | Description |
|---|---|
| [`openartifact`](charts/openartifact) | OpenArtifact server, with optional CloudNativePG database |

## Usage

Charts are published both as OCI artifacts and as a classic Helm repository:

```sh
# OCI
helm install openartifact oci://ghcr.io/openartifact/charts/openartifact

# Classic repository
helm repo add openartifact https://openartifact.github.io/helm-charts
helm repo update
helm install openartifact openartifact/openartifact
```

See the [chart README](charts/openartifact/README.md) for configuration.

### Verifying charts

From 0.1.2, every release is signed twice:

- **Helm provenance** (`.prov`, GPG key `2CB2 1818 4F57 3BAA FC53 2E84 D4DE 9B5D 6FDD 2ACD`,
  [`pgp_keys.asc`](https://openartifact.github.io/helm-charts/pgp_keys.asc)):

  ```sh
  curl -fsSL https://openartifact.github.io/helm-charts/pgp_keys.asc | gpg --dearmor > openartifact-charts.gpg
  helm install openartifact openartifact/openartifact --verify --keyring openartifact-charts.gpg
  ```

- **cosign keyless** on the OCI artifact:

  ```sh
  cosign verify ghcr.io/openartifact/charts/openartifact:0.1.2 \
    --certificate-identity-regexp '^https://github.com/openartifact/helm-charts/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

## Development

```sh
helm lint charts/openartifact -f charts/openartifact/ci/cnpg-values.yaml
ct lint --config ct.yaml
```

Pull requests run `ct lint` and `ct install` on a kind cluster with the CloudNativePG
operator (values from `charts/*/ci/*-values.yaml`). Every chart change MUST bump
`version` in `Chart.yaml`; bump `appVersion` when tracking a new OpenArtifact release.

## Releasing

Merging to `main` publishes every chart version that has no release yet:

- a GitHub release `<chart>-<version>` and the `index.yaml` on the `gh-pages` branch
  (served at <https://openartifact.github.io/helm-charts>);
- `oci://ghcr.io/openartifact/charts/<chart>:<version>`.

## License

[AGPL-3.0-or-later](LICENSE), like OpenArtifact itself. The repository follows
[REUSE](https://reuse.software).
