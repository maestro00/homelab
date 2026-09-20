# Homepage Dashboard Design

Replaces Homarr with [Homepage](https://gethomepage.dev) (v1.2.0) as the
homelab dashboard. Homarr's config lives in a Postgres DB managed through its
UI, so it is not IaC. Homepage is configured entirely with YAML in one Helm
values file, so every change is a git push that auto-deploys through Forgejo
Actions.

## Decision

| Piece      | Choice                        | Why                                     |
| ---------- | ----------------------------- | --------------------------------------- |
| App        | gethomepage.dev `v1.2.0`      | YAML-only config, no DB, no UI wizard   |
| Chart      | `jameswynn/homepage` `v2.1.0` | Config inlined in one `values.yaml`     |
| Namespace  | `homepage`                    | matches repo convention                 |
| Exposure   | ClusterIP :3000 via Caddy     | same pattern as homarr, no MetalLB IP   |
| Endpoint   | `home.yukselcloud.com`        | Caddy + DDNS workflows already exist    |
| GitOps     | `.forgejo/workflows/`         | `helm upgrade --install` on push        |
| Auth       | none in phase 1               | follow-up issue: Authelia forward-auth  |

## Phase 1 scope

Ship a working dashboard with no API keys required.

1. Create `k3s-ha-cluster/homepage/values.yaml`:

   - `enableRbac: true` and `serviceAccount.create: true` to power the
     Kubernetes integration (chart RBAC already grants ingress, node,
     namespace and `metrics.k8s.io` access).
   - `env.HOMEPAGE_ALLOWED_HOSTS=home.yukselcloud.com`.
   - `config.settings`: title, theme, header style, layout order.
   - `config.services`: full launcher grid ported from the abandoned Homer
     config — Infrastructure, Git & DevOps, Identity & Security, Networking &
     DNS, Media, Monitoring. Adds beszel, uptime-kuma, opengym, portfolio,
     ntfy.
   - `config.widgets`: Kubernetes info widget (cluster + per-node CPU/RAM),
     Longhorn widget (volume stats), speedtest, ntfy, greeting, search.
   - `config.kubernetes` with `mode: cluster`.

2. Create `k3s-ha-cluster/homepage/secret.yaml` with placeholder keys for
   phase-2 widgets (sonarr/radarr/beszel/proxmox/forgejo tokens).

3. Add Caddy route in `k3s-ha-cluster/caddy/configmap.yaml`:

   ```caddyfile
   home.yukselcloud.com {
       log
       crowdsec
       reverse_proxy homepage.homepage.svc.cluster.local:3000
   }
   ```

4. Add subdomain in `k3s-ha-cluster/ddns/config.json`:

   ```json
   { "name": "home", "proxied": false }
   ```

5. Create `.forgejo/workflows/deploy-homepage.yml` mirroring the homer
   workflow pattern. The runner image (`kubectl-node:latest`) has no Helm, so
   the workflow first installs a pinned Helm binary, then runs:

   ```bash
   helm upgrade --install homepage jameswynn/homepage -n homepage \
       -f k3s-ha-cluster/homepage/values.yaml
   ```

   plus `helm repo add jameswynn` beforehand, and `kubectl apply -f
   secret.yaml` after. Helm renders the config into ConfigMaps and the chart
   reloads the pod when the config checksum changes.

6. Delete the abandoned `k3s-ha-cluster/homer/` folder and
   `.forgejo/workflows/homer-deploy.yml`.

## Phase 2 scope

Tracked as Forgejo issues with the `homepage` label. Each item is still IaC —
a values.yaml or manifest change.

1. **API-key widgets**: sonarr, radarr, prowlarr, qbittorrent, jellyfin,
   beszel, proxmox, grafana, pi-hole. Source the keys, store them in the
   homepage secret, reference via `envFrom` → `HOMEPAGE_VAR_*`.
2. **Forgejo Actions widget**: homepage has no native widget. Use the
   `customapi` widget against
   `https://git.yukselcloud.com/api/v1/repos/lab/homelab/actions/runs` with
   the existing `FORGEJO_TOKEN`. Token stays in the cluster; homepage proxies
   server-side.
3. **Kubernetes auto-discovery**: this cluster has no Ingress objects (Caddy
   reads a ConfigMap), so discovery has nothing to read. Plan: add inert
   `networking.k8s.io/v1` marker Ingresses annotated with `gethomepage.dev/*`
   and an explicit href. No controller claims them.

   > Discovery buys little here: nothing changes without a git push anyway,
   > so this is the lowest-priority issue. Note that homepage does not yet
   > support multiple widgets per service via annotations, so widget-heavy
   > services stay in `services.yaml`.

4. **Decommission homarr**: remove its Caddy route, its Authelia OIDC
   client, the namespace, and the `k3s-ha-cluster/homarr/` folder. Do this
   after homepage is verified live.

## Cutover

Order of operations when applying this spec:

1. Create homepage folder, values, secret, workflow.
2. Add Caddy route + DDNS subdomain, push everything.
3. Verify `home.yukselcloud.com` serves the dashboard and widgets render.
4. Delete homer remnants.
5. File the phase-2 issues with the `homepage` label.

## Out of scope

- Custom CSS/themes beyond built-in settings.
- Public vs private split (all links stay on the one dashboard).
- Docker provider (no Docker API access from the cluster).