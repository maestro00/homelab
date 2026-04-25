---
name: homelab-k3s
description: >
  Expert guide for Tay's yukselcloud.com K3s HA cluster — services, Helm, kubectl, Forgejo
  GitOps CI/CD, and infrastructure patterns. Use this skill whenever Tay asks about:
  deploying or configuring any service on the cluster, writing Helm values files, adding
  new namespaces, exposing services via Caddy or MetalLB, CrowdSec bouncer integration,
  Authelia SSO, debugging pods, kubectl commands, Longhorn storage, Forgejo Actions
  workflows, or anything K3s/Kubernetes related. Trigger immediately on any mention of:
  helm, kubectl, k3s, namespace names (media, auth, caddy, monitoring, forgejo, crowdsec,
  db, security, etc.), service names (jellyfin, radarr, sonarr, authelia, grafana,
  vaultwarden, crowdsec, mysql, termix, etc.), Forgejo workflows, or any homelab service
  deployment question.
---

# Homelab K3s Skill

Full context of Tay's K3s HA cluster, including real repo structure, Caddy config, and
GitOps workflow. Always give topology-aware, pattern-consistent answers.
Tay is actively learning — explain concepts before showing config.

---

## Cluster Overview

- **Distribution**: K3s HA (5 nodes, 3 control planes, 2 workers)
- **Domain**: `yukselcloud.com` (Cloudflare DNS + DDNS updater)
- **Git server**: Forgejo at `git.yukselcloud.com` (primary), mirrored to GitHub
- **Ingress**: Caddy (custom, NOT traefik/nginx) — image `ghcr.io/serfriz/caddy-cloudflare-crowdsec`
- **Load Balancer**: MetalLB (IP pool: `192.168.0.200–192.168.0.229`)
- **Storage**: Longhorn (replicated across 171/172/181/182 — Pi excluded via taint)
- **Auth**: Authelia (Helm, `auth` namespace) + lldap + Redis
- **Security**: CrowdSec (DaemonSet agents + LAPI) integrated directly into Caddy bouncer
- **DB**: CloudNativePG for PostgreSQL (Forgejo), Bitnami MySQL Helm chart (`db` namespace)
- **K3s datastore**: External MariaDB on bare metal (Proxmox host, `192.168.0.52`)
- **VIP**: kube-vip at `192.168.0.100` for K3s API HA

---

## Node Topology

| Node | IP | Arch | K3s Role | Notes |
|------|----|------|----------|-------|
| `infra-pi` | 192.168.0.10 | ARM64 | Control plane | Pi-hole runs here; tainted from Longhorn |
| `k8s-node-171` | 192.168.0.171 | AMD64 | Control plane | `master-ingress`, Longhorn-enabled |
| `k8s-node-172` | 192.168.0.172 | AMD64 | Worker | Longhorn-enabled |
| `k8s-node-181` | 192.168.0.181 | AMD64 | Control plane | `master-ingress`, Longhorn-enabled |
| `k8s-node-182` | 192.168.0.182 | AMD64 | Worker | Longhorn-enabled |

**Caddy nodeSelector**: `role: master-ingress` → runs only on 171 and 181
**Longhorn taint on Pi**: `node-role.kubernetes.io/no-longhorn=:NoSchedule`
**Longhorn label on workers**: `storage-with-longhorn=true` (required by Longhorn node selector)

---

## Repo Structure (`k3s-ha-cluster/`)

```
k3s-ha-cluster/
├── .forgejo/workflows/         # GitOps CI/CD — auto-deploy on push to Forgejo
├── auth/
│   ├── README.md
│   ├── authelia/values.yaml    # Helm values (OIDC clients, access rules, secrets refs)
│   ├── authelia/secret.yaml    # Authelia secrets (HMAC, session, storage keys)
│   ├── lldap/                  # Custom Helm chart
│   └── redis/                  # Redis for Authelia sessions
├── caddy/
│   ├── configmap.yaml          # *** THE Caddyfile — edit to add/change routes ***
│   ├── deployment.yaml         # nodeSelector: master-ingress; mounts configmap + PVC
│   ├── service.yaml            # externalTrafficPolicy: Local (REQUIRED for CrowdSec)
│   ├── pvc.yaml                # Longhorn PVC for /data (TLS certs storage)
│   └── crowdsec-bouncer-secret.yaml  # CROWDSEC_API_KEY env var for Caddy
├── forgejo/
│   ├── values.yaml             # Helm values (OCI chart: code.forgejo.org)
│   ├── postgres/               # CNPG PostgreSQL cluster manifests
│   ├── runner/                 # Custom Helm chart for Forgejo Actions runner
│   └── admin-secret.yaml
├── media/
│   ├── Chart.yaml              # Umbrella chart
│   ├── templates/              # Shared deployment.yaml + service.yaml templates
│   ├── pv.yaml                 # NFS PersistentVolumes (NFS: 192.168.0.52)
│   ├── pvc.yaml                # PVCs for all media apps
│   ├── sonarr/values.yaml
│   ├── radarr/values.yaml
│   ├── bazarr/values.yaml
│   ├── prowlarr/values.yaml
│   ├── flaresolverr/values.yaml
│   ├── jellyfin/values.yaml
│   ├── qbittorrent/            # Raw manifests — Gluetun VPN sidecar
│   └── seerr/values.yaml
├── monitoring/values.yaml      # kube-prometheus-stack Helm values
├── mysql/
│   ├── README.md
│   ├── values.yaml             # Bitnami MySQL Helm values
│   └── secret.yaml             # root/replication/crowdsec passwords
├── security/crowdsec/
│   ├── README.md
│   ├── values.yaml             # bouncer key, ENROLL_KEY, MySQL DB config
│   └── mysql-secret.yaml       # copy of MySQL password for crowdsec namespace
├── vaultwarden/values.yaml     # guerzon/vaultwarden chart
├── homer/
│   ├── values.yaml             # djjudas21/homer chart
│   └── config.yaml             # Dashboard links and layout
├── termix/                     # Custom Helm chart (helm install termix ./termix)
├── kubernetes-dashboard/
│   ├── values.yaml
│   ├── service-account.yaml
│   └── rbac.yaml
└── stirling-pdf/               # Helm chart
```

---

## Namespace & MetalLB IP Map

| Namespace | Key Services | External IP | Deploy Method |
|-----------|-------------|-------------|---------------|
| `auth` | authelia, lldap, redis | lldap: 192.168.0.205 | Helm |
| `caddy` | caddy (2 replicas on master-ingress nodes) | 192.168.0.201 | Raw manifests |
| `crowdsec` | crowdsec-agent (DS), crowdsec-lapi | 192.168.0.206 | Helm |
| `db` | mysql | 192.168.0.207 | Helm (Bitnami) |
| `ddns` | cloudflare-ddns | — | Raw manifest |
| `forgejo` | forgejo, forgejo-pg (CNPG), runner | — | Helm (OCI) |
| `homer` | homer | 192.168.0.208 | Helm |
| `kubernetes-dashboard` | dashboard | 192.168.0.209 | Helm |
| `longhorn-system` | longhorn | 192.168.0.203 | Helm |
| `media` | qbittorrent, prowlarr, radarr, sonarr, bazarr, jellyfin, seerr, flaresolverr, profilarr, metube, scraperr | 192.168.0.210–222 | Custom Helm umbrella |
| `monitoring` | prometheus, grafana, alertmanager, node-exporter | grafana: ClusterIP | Helm (kube-prometheus-stack) |
| `speedtest-tracker` | speedtest-tracker | 192.168.0.223 | — |
| `stirling-pdf` | stirling-pdf | 192.168.0.224 | Helm |
| `termix` | termix | 192.168.0.216 | Custom Helm chart |
| `vaultwarden` | vaultwarden | 192.168.0.204 | Helm |

> **Next available MetalLB IP**: `192.168.0.225`

---

## GitOps Workflow (Forgejo Actions)

Changes auto-deploy on push. Every service folder should have a matching workflow.

```yaml
# .forgejo/workflows/deploy-<service>.yaml
name: Deploy <Service>
on:
  push:
    paths:
      - "k3s-ha-cluster/<service>/**"   # trigger only on relevant changes
jobs:
  deploy:
    runs-on: self-hosted
    container:
      image: git.yukselcloud.com/lab/kubectl-node:latest  # custom image with kubectl
    steps:
      - uses: actions/checkout@v4
      - name: Setup Kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_DEPLOY }}" > ~/.kube/config
          chmod 600 ~/.kube/config
      - name: Apply
        run: kubectl -n <namespace> apply -f k3s-ha-cluster/<service>/
      - name: Rollout Restart          # include if ConfigMap changed
        run: kubectl -n <namespace> rollout restart deploy <n>
```

**Key facts:**
- Runner: `forgejo-runner` pod in `forgejo` namespace (self-hosted)
- Runner image: `git.yukselcloud.com/lab/kubectl-node:latest`
- Secret: `KUBECONFIG_DEPLOY` (Forgejo repo secret)
- For Helm deploys: use `helm upgrade --install ...` in the workflow step instead of `kubectl apply`
- For ConfigMap-only changes (like Caddy): apply + rollout restart

---

## Deployment Decision: Helm vs Raw Manifests

| Approach | When to use | Examples |
|----------|-------------|---------|
| **Upstream Helm chart** (preferred) | Maintained chart exists | Authelia, Vaultwarden, MySQL, Homer, Prometheus, Forgejo, Stirling PDF |
| **Custom Helm chart** | No upstream chart or too complex | `media/` (umbrella), `termix/`, `auth/lldap/`, `forgejo/runner/` |
| **Raw manifests** | Simple service or multi-container | Caddy, DDNS, qBittorrent+Gluetun |

Always use Helm when possible. Raw manifests only when a chart can't handle the setup (e.g. qBittorrent needs Gluetun VPN sidecar with shared network namespace).

---

## Reference Files

- `references/caddy-crowdsec.md` — Real Caddyfile patterns, CrowdSec integration, Authelia forward-auth, adding new routes
- `references/patterns.md` — Helm values conventions, manifest templates, media stack, database patterns
- `references/kubectl-workflows.md` — kubectl commands scoped to this cluster
