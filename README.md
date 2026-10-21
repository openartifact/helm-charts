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
