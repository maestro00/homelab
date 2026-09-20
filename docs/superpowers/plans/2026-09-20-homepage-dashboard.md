# Homepage Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Homepage (gethomepage.dev) as the homelab dashboard on K3s,
fully IaC via one Helm values file, exposed at `home.yukselcloud.com`.

**Architecture:** A `jameswynn/homepage` Helm chart in a new `homepage`
namespace renders the whole dashboard from `k3s-ha-cluster/homepage/values.yaml`
(settings, services grid, widgets, Kubernetes config). A ClusterIP service is
routed through Caddy; a Forgejo Actions workflow deploys on push. The runner
image already carries Helm v3.18.4 (built and pushed in the design phase).

**Tech Stack:** Helm (chart `jameswynn/homepage` v2.1.0), image
`ghcr.io/gethomepage/homepage` v1.2.0, K3s, Caddy, Cloudflare DDNS,
Forgejo Actions, Forgejo REST API.

## Global Constraints

- Pin the image tag `v1.2.0` — never `:latest` (repo convention).
- Config source of truth is the single file `k3s-ha-cluster/homepage/values.yaml`.
- Namespace `homepage`, ClusterIP only — no MetalLB IP (Caddy handles routing).
- Workflow pattern matches `beszel`/`homer` conventions: runner image
  `git.yukselcloud.com/lab/kubectl-node:latest`, secret `KUBECONFIG_DEPLOY`,
  ntfy notify via `http://ntfy.ntfy.svc.cluster.local/homelab-deploys`.
- Icons are full homarr-labs raw URLs (each name verified 200).
- Any `.md` file written follows `markdown-rules` skill.
- No API keys in commit scope — `secret.yaml` holds empty placeholders; real
  keys land in the phase-2 API-key widget issue.

---

### Task 1: Write `k3s-ha-cluster/homepage/values.yaml`

**Files:**
- Create: `k3s-ha-cluster/homepage/values.yaml`

**Interfaces:**
- Produces: the chart override file used by the workflow (Task 4) and by the
  local render check in this task. Names the secret `homepage-secrets`
  (consumed by Task 2) and defines the settings/services/widgets homepage
  will render.

- [ ] **Step 1: Create the folder and the values file**

```bash
mkdir -p k3s-ha-cluster/homepage
```

```yaml
image:
  repository: ghcr.io/gethomepage/homepage
  tag: v1.2.0

enableRbac: true

serviceAccount:
  create: true

service:
  main:
    type: ClusterIP
    ports:
      http:
        port: 3000

env:
  - name: HOMEPAGE_ALLOWED_HOSTS
    value: "home.yukselcloud.com"
  - name: LONGHORN_URI
    value: "http://longhorn-frontend.longhorn-system.svc.cluster.local"

envFrom:
  - secretRef:
      name: homepage-secrets

resources:
  requests:
    memory: 128Mi
    cpu: 50m
  limits:
    memory: 512Mi
    cpu: 500m

config:
  settings:
    title: YukselCloud Homelab
    theme: dark
    headerStyle: boxed
    statusStyle: dot
    language: en

  widgets:
    - greeting:
        text_size: xl
        text: YukselCloud Homelab
    - kubernetes:
        cluster:
          show: true
          cpu: true
          memory: true
          showLabel: true
          label: cluster
        nodes:
          show: true
          cpu: true
          memory: true
          showLabel: true
    - longhorn:
        expanded: true
        total: true
        nodes: true

  services:
    - Infrastructure:
        - Longhorn:
            href: http://192.168.0.203
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/longhorn.png
            description: Persistent storage UI
        - Kubernetes Dashboard:
            href: https://192.168.0.209
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/kubernetes.png
            description: Cluster management

    - Git & DevOps:
        - Forgejo:
            href: https://git.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/forgejo.png
            description: Self-hosted git
        - Termix:
            href: http://192.168.0.216:8080
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/terminal.png
            description: Terminal multiplexer

    - Identity & Security:
        - Authelia:
            href: https://auth.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/authelia.png
            description: 2FA & SSO
        - Vaultwarden:
            href: https://vaultwarden.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/vaultwarden.png
            description: Password manager
        - lldap:
            href: https://ldap.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/lldap.png
            description: LDAP directory

    - Networking & DNS:
        - Pi-hole:
            href: https://pihole.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/pi-hole.png
            description: DNS & ad-block
        - Tailscale:
            href: https://login.tailscale.com/admin
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/tailscale.png
            description: VPN overlay admin

    - Media:
        - Sonarr:
            href: http://192.168.0.212:8989
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/sonarr.png
            description: TV show management
        - Radarr:
            href: http://192.168.0.213:7878
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/radarr.png
            description: Movie management
        - Prowlarr:
            href: http://192.168.0.211:9696
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/prowlarr.png
            description: Indexer management
        - Bazarr:
            href: http://192.168.0.214:6767
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/bazarr.png
            description: Subtitle management
        - Flaresolverr:
            href: http://192.168.0.217:8191
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/flaresolverr.png
            description: CAPTCHA solver
        - Jellyfin:
            href: http://192.168.0.215:8096
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/jellyfin.png
            description: Media playback
        - Jellyseerr:
            href: http://192.168.0.218:5055
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/jellyseerr.png
            description: Media requests
        - Profilarr:
            href: http://192.168.0.219:6868
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/profilarr.png
            description: Media profiling
        - Metube:
            href: http://192.168.0.222:8080
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/metube.png
            description: YouTube downloader
        - qBittorrent:
            href: http://192.168.0.210:8080
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/vuetorrent.png
            description: Torrent client

    - Observability:
        - Grafana:
            href: https://grafana.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/grafana.png
            description: Monitoring dashboards
        - Speedtest Tracker:
            href: http://192.168.0.223
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/speedtest-tracker.png
            description: Bandwidth history
            widget:
              type: speedtest
              url: http://speedtest-tracker.speedtest-tracker.svc.cluster.local
        - Beszel:
            href: https://beszel.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/beszel.png
            description: Server monitoring
        - Uptime Kuma:
            href: https://uptime-kuma.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/uptime-kuma.png
            description: Uptime checks

    - Tools:
        - ntfy:
            href: https://ntfy.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/ntfy.png
            description: Push notifications
            widget:
              type: ntfy
              url: http://ntfy.ntfy.svc.cluster.local
              topic: homelab-deploys
        - OpenGym:
            href: https://opengym.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/opengym.png
            description: Workout tracking
        - Portfolio:
            href: https://portfolio.yukselcloud.com
            icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/homepage.png
            description: Personal site

  kubernetes:
    mode: cluster
```

- [ ] **Step 2: Render the chart locally to catch YAML/chart errors**

Run:

```bash
helm repo add jameswynn https://jameswynn.github.io/helm-charts
helm repo update jameswynn
helm template homepage jameswynn/homepage -n homepage \
    -f k3s-ha-cluster/homepage/values.yaml > /tmp/homepage-render.yaml
```

Expected: no errors; the file contains a `ConfigMap` whose data carries
`settings.yaml`, `services.yaml`, `widgets.yaml`, `kubernetes.yaml`, and a
`ClusterRole` plus `ClusterRoleBinding` (from `enableRbac`).

- [ ] **Step 3: Verify the rendered manifests are valid for the cluster**

Run:

```bash
kubectl apply --dry-run=client -f /tmp/homepage-render.yaml 2>&1 | tail -5
grep -c "homepage-secrets" /tmp/homepage-render.yaml
grep -c "mode: cluster" /tmp/homepage-render.yaml
```

Expected: dry-run reports no schema errors; `homepage-secrets` appears (the
`envFrom`), `mode: cluster` appears (kubernetes.yaml). Do not apply yet —
the secret must exist first (Task 2).

- [ ] **Step 4: Commit**

```bash
git add k3s-ha-cluster/homepage/values.yaml
git commit -m "feat(homepage): add helm values for homepage dashboard"
```

---

### Task 2: Write `k3s-ha-cluster/homepage/secret.yaml`

**Files:**
- Create: `k3s-ha-cluster/homepage/secret.yaml`

**Interfaces:**
- Consumes: the secret name `homepage-secrets` referenced by
  `envFrom` in Task 1.
- Produces: the Secret the workflow applies before `helm upgrade` (Task 6),
  and the home of phase-2 widget API keys via `HOMEPAGE_VAR_*` (follow-up
  issue, not this plan).

- [ ] **Step 1: Create the placeholder secret**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: homepage-secrets
  namespace: homepage
type: Opaque
stringData:
  # Phase 2 — API-key widgets. Empty values keep the pod startable in
  # phase 1. Keys map to HOMEPAGE_VAR_<NAME> env vars in the pod.
  HOMEPAGE_VAR_SONARR_API_KEY: ""
  HOMEPAGE_VAR_RADARR_API_KEY: ""
  HOMEPAGE_VAR_PROWLLARR_API_KEY: ""
  HOMEPAGE_VAR_QBITTORRENT_PASS: ""
  HOMEPAGE_VAR_QBITTORRENT_USER: ""
  HOMEPAGE_VAR_JELLYFIN_API_KEY: ""
  HOMEPAGE_VAR_BESZEL_PASS: ""
  HOMEPAGE_VAR_PROXMOX_USER: ""
  HOMEPAGE_VAR_PROXMOX_PASS: ""
  HOMEPAGE_VAR_GRAFANA_USER: ""
  HOMEPAGE_VAR_GRAFANA_PASS: ""
  HOMEPAGE_VAR_FORGEJO_TOKEN: ""
```

- [ ] **Step 2: Validate**

Run:

```bash
kubectl create namespace homepage --dry-run=client -o yaml > /dev/null &&
kubectl apply --dry-run=client -f k3s-ha-cluster/homepage/secret.yaml
```

Expected: `secret/homepage-secrets configured (dry run)` style output, no
schema errors.

- [ ] **Step 3: Commit**

```bash
git add k3s-ha-cluster/homepage/secret.yaml
git commit -m "feat(homepage): add placeholder secrets template"
```

---

### Task 3: Write `k3s-ha-cluster/homepage/README.md`

**Files:**
- Create: `k3s-ha-cluster/homepage/README.md`

**Interfaces:**
- Produces: the operations doc for this service, following the READMEs in
  `homarr/` and `monitoring/beszel/` as precedent.

- [ ] **Step 1: Create the README**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add k3s-ha-cluster/homepage/README.md
git commit -m "docs(homepage): add README"
```

---

### Task 4: Write `.forgejo/workflows/deploy-homepage.yml`

**Files:**
- Create: `.forgejo/workflows/deploy-homepage.yml`

**Interfaces:**
- Consumes: `k3s-ha-cluster/homepage/values.yaml` (Task 1),
  `k3s-ha-cluster/homepage/secret.yaml` (Task 2), runner image with Helm
  (already built/pushed), Forgejo secret `KUBECONFIG_DEPLOY`.
- Produces: the automated deploy that triggers on every push touching
  `k3s-ha-cluster/homepage/**`.

- [ ] **Step 1: Create the workflow file**

```yaml
name: Deploy Homepage
on:
  push:
    paths:
      - "k3s-ha-cluster/homepage/**"
  workflow_dispatch:

jobs:
  deploy-homepage:
    runs-on: self-hosted

    container:
      image: git.yukselcloud.com/lab/kubectl-node:latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_DEPLOY }}" > ~/.kube/config
          chmod 600 ~/.kube/config

      - name: Ensure Namespace
        run: |
          kubectl create namespace homepage --dry-run=client -o yaml \
            | kubectl apply -f -

      - name: Apply Secrets
        run: kubectl -n homepage apply -f k3s-ha-cluster/homepage/secret.yaml

      - name: Helm Upgrade
        run: |
          helm repo add jameswynn https://jameswynn.github.io/helm-charts
          helm repo update jameswynn
          helm upgrade --install homepage jameswynn/homepage \
            --namespace homepage \
            --values k3s-ha-cluster/homepage/values.yaml

      - name: Notify
        if: always()
        run: |
          STATUS="${{ job.status }}"
          PRIORITY=$([[ "$STATUS" == "success" ]] && echo "default" || echo "high")
          TAGS=$([[ "$STATUS" == "success" ]] && echo "white_check_mark" || echo "warning")
          curl -sf \
            -H "Title: homepage deploy: $STATUS" \
            -H "Priority: $PRIORITY" \
            -H "Tags: $TAGS" \
            -d "Homepage helm upgrade — $STATUS" \
            http://ntfy.ntfy.svc.cluster.local/homelab-deploys
```

- [ ] **Step 2: Lint the YAML**

Run:

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.forgejo/workflows/deploy-homepage.yml')); print('valid yaml')"
```

Expected: `valid yaml`.

- [ ] **Step 3: Commit**

```bash
git add .forgejo/workflows/deploy-homepage.yml
git commit -m "ci(homepage): add gitops deploy workflow"
```

---

### Task 5: Expose via Caddy and DDNS

**Files:**
- Modify: `k3s-ha-cluster/caddy/configmap.yaml`
- Modify: `k3s-ha-cluster/ddns/config.json`

**Interfaces:**
- Consumes: ClusterIP service `homepage.homepage.svc.cluster.local:3000`
  created by the chart (Task 6 rollout).
- Produces: the `home.yukselcloud.com` route and DNS record; the existing
  `caddy-upgrade.yml` and `deploy-ddns.yml` workflows pick these up
  automatically.

- [ ] **Step 1: Add the Caddy route**

Insert this block after the `homarr.yukselcloud.com` block (around line 93)
in `k3s-ha-cluster/caddy/configmap.yaml`:

```caddyfile
home.yukselcloud.com {
    log
    crowdsec
    reverse_proxy homepage.homepage.svc.cluster.local:3000 {
        header_up Host {host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-For {remote_host}
    }
}
```

- [ ] **Step 2: Add the DDNS subdomain**

Add the `home` entry to the `subdomains` array in
`k3s-ha-cluster/ddns/config.json` (keep the trailing comma rules of JSON):

```json
{
    "name": "home",
    "proxied": false
}
```

- [ ] **Step 3: Validate both files**

Run:

```bash
python3 -m json.tool k3s-ha-cluster/ddns/config.json > /dev/null && echo "json ok"
grep -n "home.yukselcloud.com" k3s-ha-cluster/caddy/configmap.yaml
```

Expected: `json ok` and a line for `home.yukselcloud.com`.

- [ ] **Step 4: Commit**

```bash
git add k3s-ha-cluster/caddy/configmap.yaml k3s-ha-cluster/ddns/config.json
git commit -m "feat(homepage): expose home.yukselcloud.com via caddy + ddns"
```

---

### Task 6: Roll out via GitOps and verify live

**Files:**
- None created — execution task.

**Interfaces:**
- Consumes: all files from Tasks 1-5.
- Produces: live dashboard at `home.yukselcloud.com`.

- [ ] **Step 1: Push to Forgejo**

```bash
git push
```

Expected: push lands on `master`; Forgejo Actions starts the homepage,
caddy-upgrade and ddns workflows.

- [ ] **Step 2: Wait for the homepage deploy job**

Run:

```bash
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  "https://git.yukselcloud.com/api/v1/repos/lab/homelab/actions/tasks" \
  | jq -r '.workflow_runs[] | select(.name == "Deploy Homepage") | .status'
```

Expected: `success` within a few minutes. (If `$FORGEJO_TOKEN` is unset in
the shell, read it from the podman or git credential store as available;
otherwise ask Tay.)

- [ ] **Step 3: Check the pod and its RBAC**

Run:

```bash
kubectl -n homepage get pods
kubectl -n homepage logs deploy/homepage --tail=10
```

Expected: pod `Running`/`Ready`; logs free of fatal config errors (a single
READY line is typical). If `envFrom` complains, the secret did not exist
before the deployment — re-run the workflow.

- [ ] **Step 4: Verify the site responds**

Run:

```bash
curl -sI https://home.yukselcloud.com | head -5
```

Expected: HTTP 200 (or a redirect to HTTPs that resolves), served by Caddy.

- [ ] **Step 5: Verify widgets render data**

Run:

```bash
kubectl -n homepage logs deploy/homepage --tail=40 | grep -iE "error|warn"
```

Expected: no widget proxy errors for kubernetes/longhorn. Spot-check in the
browser: cluster CPU/RAM per node, Longhorn volume counts, speedtest and
ntfy widgets show numbers.

- [ ] **Step 6: Confirm Caddy + DDNS flows**

Run:

```bash
kubectl -n caddy rollout status deploy/caddy --timeout=60s
kubectl -n ddns rollout status deploy/cloudflare-ddns --timeout=60s
nslookup home.yukselcloud.com 2>/dev/null | tail -3
```

Expected: both deployments rolled out; DNS resolves to the cluster
external IP.

---

### Task 7: Remove the abandoned Homer dashboard

**Files:**
- Delete: `k3s-ha-cluster/homer/`
- Delete: `.forgejo/workflows/homer-deploy.yml`

**Interfaces:**
- Consumes: nothing (Homer was never deployed — the namespace does not
  exist; verified during design).
- Produces: a clean repo with exactly one dashboard implementation.

- [ ] **Step 1: Delete the files**

```bash
rm -rf k3s-ha-cluster/homer .forgejo/workflows/homer-deploy.yml
```

- [ ] **Step 2: Verify nothing references homer**

Run:

```bash
grep -rn "homer" k3s-ha-cluster/caddy/configmap.yaml k3s-ha-cluster/ddns/config.json || echo "no refs"
```

Expected: `no refs`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove abandoned homer dashboard"
```

---

### Task 8: File phase-2 issues with the `homepage` label

**Files:**
- None — Forgejo REST API calls.

**Interfaces:**
- Consumes: Forgejo API token (ask Tay or use the stored credential;
  `FORGEJO_TOKEN` from the podman/git credential store has worked for
  pushes).
- Produces: the label `homepage` and five issues in `lab/homelab` that
  track the phase-2 work.

- [ ] **Step 1: Create the `homepage` label**

Run:

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/labels" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"homepage","description":"Homepage dashboard service","color":"#36a2eb"}'
```

Expected: the label JSON with an `id`.

- [ ] **Step 2: Create issue 1 — API-key widgets**

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "homepage: wire API-key widgets (sonarr/radarr/prowlarr/qbittorrent/jellyfin/beszel/proxmox/grafana)",
    "body": "Add live service widgets to the dashboard (issue family: homepage).\n\n## Services and keys needed\n- sonarr, radarr, prowlarr — API keys\n- qbittorrent — username/password\n- jellyfin — API key\n- beszel — password\n- proxmox — API token (user@realm!tokenid)\n- grafana — service account token\n- pi-hole — (optional) password\n\n## Steps\n1. Collect each key from the running app (UI/API/config)\n2. Fill `k3s-ha-cluster/homepage/secret.yaml` values (never commit real ones)\n3. Reference with `${HOMEPAGE_VAR_*}` in `widget.key` in `values.yaml`\n4. Push — workflow redeploys; verify each widget shows data\n\nWidget types: homepage `sonarr`, `radarr`, `prowlarr`, `qbittorrent`, `jellyfin`, `beszel`, `proxmox`, `grafana`.",
    "labels": ["homepage"]
  }'
```

- [ ] **Step 3: Create issue 2 — Forgejo Actions widget**

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "homepage: Forgejo Actions widget via customapi",
    "body": "Show CI workflow runs on the dashboard.\n\n## Approach\nHomepage has a `gitea` widget (repos/issues counts) but no Actions widget. Use the `customapi` widget against:\n\n`https://git.yukselcloud.com/api/v1/repos/lab/homelab/actions/runs?limit=5`\n\nwith header `Authorization: token ${HOMEPAGE_VAR_FORGEJO_TOKEN}`. Homepage proxies server-side, so the token never leaves the cluster.\n\n## Steps\n1. Fill `HOMEPAGE_VAR_FORGEJO_TOKEN` in the secret\n2. Attach a `customapi` widget to the Forgejo card in `values.yaml` (mapping: run name + status per entry)\n3. Verify last-run status renders",
    "labels": ["homepage"]
  }'
```

- [ ] **Step 4: Create issue 3 — Kubernetes auto-discovery**

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "homepage: Kubernetes service discovery via marker Ingresses",
    "body": "Homepage discovers services by reading Ingress objects annotated with `gethomepage.dev/*`. This cluster routes via Caddy (no Ingress objects exist), so discovery has nothing to read.\n\n## Plan\nAdd inert `networking.k8s.io/v1` Ingresses (no `ingressClassName`, no controller claims them) per service with:\n\n- `gethomepage.dev/enabled: \"true\"`\n- `gethomepage.dev/name`, `gethomepage.dev/group`, `gethomepage.dev/icon`\n- `gethomepage.dev/href: \"<public url>\"` (explicit, since no controller fills the rule)\n\nHomepage RBAC already grants `ingresses` list/get.\n\n## Note\nDiscovery buys little here — nothing changes without a git push, and multiple widgets per service are not supported via annotations. Lowest priority; keep widget-heavy services in `values.yaml`.",
    "labels": ["homepage"]
  }'
```

- [ ] **Step 5: Create issue 4 — decommission homarr**

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "homepage: decommission homarr",
    "body": "Homepage replaced Homarr. Remove it once the new dashboard is verified live.\n\n## Steps\n1. Remove `homarr.yukselcloud.com` route from `caddy/configmap.yaml`\n2. Remove `homarr` from `ddns/config.json`\n3. Remove the `homarr` OIDC client from `auth/authelia/values.yaml`\n4. Delete namespace: `kubectl delete ns homarr`\n5. Delete `k3s-ha-cluster/homarr/` folder\n6. Drop `homarr` from the namespace/IP tables in the skill docs and README",
    "labels": ["homepage"]
  }'
```

- [ ] **Step 6: Create issue 5 — protect the dashboard**

```bash
curl -sS -X POST "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "homepage: add Authelia forward-auth",
    "body": "`home.yukselcloud.com` is currently open (like homarr was). Protect it:\n\n```caddyfile\nhome.yukselcloud.com {\n    log\n    crowdsec\n    forward_auth authelia.auth.svc.cluster.local:9091 {\n        uri /api/authz/forward-auth\n        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email\n    }\n    reverse_proxy homepage.homepage.svc.cluster.local:3000\n}\n```\n\nVerify after apply that the dashboard requires login and widgets still render.",
    "labels": ["homepage"]
  }'
```

- [ ] **Step 7: Verify the issues exist**

Run:

```bash
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues?labels=homepage&state=open" \
  | jq -r '.[] | "#\(.number) \(.title)"'
```

Expected: five issue lines tagged `homepage`.

---

## Self-review notes

- Spec coverage: every phase-1 item maps to Tasks 1-5, rollout to Task 6,
  homer removal to Task 7, all five phase-2 items to Task 8 issues. The
  runner-image Helm change was already built and pushed during design.
- Placeholder scan: no TBD/TODO; the deliberately-empty secret values are
  marked as intentional (phase 2 wiring).
- Type consistency: the secret name `homepage-secrets`, the `HOMEPAGE_VAR_*`
  names, the workflow trigger path, and the Caddy service DNS all match
  across tasks.