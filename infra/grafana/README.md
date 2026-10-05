# Grafana assets

Canonical dashboards and provisioning live next to the Kind manifests:

`infra/k8s/base/grafana/`

- `dashboards/*.json` — Executive, Triage, Infra
- `provisioning/` — datasource + dashboard provider

Loaded automatically when Grafana starts in the cluster (ConfigMaps via Kustomize).
