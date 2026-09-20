# Homepage

IaC dashboard for the homelab, configured entirely from
[`values.yaml`](values.yaml) — no UI, no database.

- Homepage (gethomepage.dev) via the `jameswynn/homepage` Helm chart
- Exposed at `home.yukselcloud.com` through Caddy (ClusterIP, no LB IP)
- Deploys via GitOps: `.forgejo/workflows/deploy-homepage.yml`
- Dashboard + widgets rendered server-side; config hot-reloads on push

## Layout

- `values.yaml` — everything: settings, service grid, widgets, k8s config
- `secret.yaml` — `HOMEPAGE_VAR_*` API keys for widgets (phase 2)

## Adding a service to the dashboard

Add a block to `config.services` in `values.yaml`:

```yaml
- My Service:
    href: https://service.yukselcloud.com
    icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/service.png
    description: What it does
```

Push to `master`. The workflow runs `helm upgrade` and the pod reloads.
Links inside the dashboard are IaC too — this file is the source of truth.

## Kubernetes integration

`mode: cluster` with `enableRbac: true` gives homepage read access for the
Kubernetes and Longhorn widgets (not service discovery — that reads Ingress
objects, which this cluster does not use; see the phase-2 marker-Ingress
issue).

## Updating the runner image

The Forgejo Actions runner image carries Helm:

```bash
cd ../forgejo/runner/image
podman build -t git.yukselcloud.com/lab/kubectl-node:latest .
podman push git.yukselcloud.com/lab/kubectl-node:latest
```