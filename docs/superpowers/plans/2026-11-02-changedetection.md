# changedetection.io Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy changedetection.io with a Playwright stealth browser so Tay can watch price/stock changes on Cloudflare-protected sites (amazon.de, vatanbilgisayar.com, gigantti.fi) and get ntfy notifications.

**Architecture:** changedetection.io (`ghcr.io/dgtlmoon/changedetection.io:0.60.10`) runs in a new `changedetection` namespace alongside a `dgtlmoon/sockpuppetbrowser:0.0.3` sidecar-style deployment. changedetection reaches the browser via `PLAYWRIGHT_DRIVER_URL=ws://sockpuppetbrowser.changedetection.svc.cluster.local:3000/?stealth=1`. The web UI is exposed at `changedetection.yukselcloud.com` through Caddy (crowdsec, app's own password). Notifications go through the existing ntfy server via apprise.

**Tech Stack:** Kubernetes raw manifests (speedtest-tracker pattern), Longhorn PVC, Caddy + DDNS (existing automation), ntfy/apprise, Forgejo Actions deploy workflow.

**Spec:** This plan is its own spec (no separate design doc); decisions are locked below.

## Global Constraints

- Namespace: `changedetection`. Domain: `changedetection.yukselcloud.com`.
- Pin images: `ghcr.io/dgtlmoon/changedetection.io:0.60.10`, `dgtlmoon/sockpuppetbrowser:0.0.3`.
- Storage: Longhorn, RWO, 5Gi datastore PVC.
- Secrets stay out of git: changedetection password via `SALTED_PASS` in a gitignored/Forgejo-secret-backed Secret (placeholder in repo).
- Use Caddy + DDNS automation (do not hand-edit live ConfigMap); MetalLB is not needed — ClusterIP service.
- Notification topic: `homelab-changedetection`.

## Review Focus

- **sockpuppetbrowser sandbox:** Chrome may crash without `SYS_ADMIN` or `/dev/shm`. Pin with `securityContext.capabilities.add: [SYS_ADMIN]` + `emptyDir` on `/dev/shm`. Verify: `kubectl -n changedetection logs deploy/sockpuppetbrowser` shows a listening server, and a test watch renders JS.
- **Interactive Cloudflare Turnstile is not auto-solvable.** Playwright stealth handles JS rendering and some managed challenges, but a full interactive CAPTCHA still needs BrowserSteps or a proxy. This is documented in the bypass issue so the expectation is set.
- **BASE_URL missing:** without `BASE_URL=https://changedetection.yukselcloud.com`, notification links point at localhost. Set it in the Deployment env.
- **ntfy token auth:** apprise needs `?auth=token` when using a bearer token (`ntfys://tk_…@ntfy.yukselcloud.com/homelab-changedetection?auth=token`), otherwise it falls back to basic auth and gets 401.
- **Playwright memory leak:** sockpuppetbrowser can grow RAM. Mitigate with a resource limit and `MAX_CONCURRENT_CHROME_PROCESSES=5`.

---

### Task 1: Deploy changedetection.io + sockpuppetbrowser

**Files:**
- Create: `k3s-ha-cluster/changedetection/namespace.yaml`
- Create: `k3s-ha-cluster/changedetection/pvc.yaml`
- Create: `k3s-ha-cluster/changedetection/secret.yaml`
- Create: `k3s-ha-cluster/changedetection/deployment.yaml`
- Create: `k3s-ha-cluster/changedetection/service.yaml`
- Create: `k3s-ha-cluster/changedetection/README.md`
- Create: `.forgejo/workflows/deploy-changedetection.yaml`

**Interfaces:**
- Produces: Service `changedetection.changedetection.svc.cluster.local:5000` (consumed by Task 2 Caddy route); Service `sockpuppetbrowser.changedetection.svc.cluster.local:3000`; Secret `changedetection-secret` (keys: `salted-pass`).

- [ ] **Step 1: Create namespace + PVC manifests**

`namespace.yaml` (kind Namespace, name changedetection). `pvc.yaml` (name `changedetection-datastore`, longhorn, RWO, 5Gi).

- [ ] **Step 2: Create secret placeholder**

`secret.yaml` uses `stringData.salted-pass: "PLACEHOLDER"` with a comment to set the real salted hash out-of-band (mirror the speedtest-tracker pattern). Do not commit a real value.

- [ ] **Step 3: Create deployment.yaml**

Two Deployments in one file (or two files). changedetection: image `ghcr.io/dgtlmoon/changedetection.io:0.60.10`, port 5000, volumeMount `/datastore` → PVC, env `PLAYWRIGHT_DRIVER_URL=ws://sockpuppetbrowser.changedetection.svc.cluster.local:3000/?stealth=1&--disable-web-security=true`, `BASE_URL=https://changedetection.yukselcloud.com`, `TZ=Europe/Helsinki`, `SALTED_PASS` from secret, resources (256Mi req / 1Gi limit). sockpuppetbrowser: image `dgtlmoon/sockpuppetbrowser:0.0.3`, port 3000, env `SCREEN_WIDTH=1920 SCREEN_HEIGHT=1024 SCREEN_DEPTH=16 MAX_CONCURRENT_CHROME_PROCESSES=5`, `securityContext.capabilities.add: [SYS_ADMIN]`, `/dev/shm` emptyDir, resources (512Mi req / 2Gi limit).

- [ ] **Step 4: Create service.yaml**

`changedetection` Service (ClusterIP, port 5000→5000, selector app: changedetection); `sockpuppetbrowser` Service (ClusterIP, port 3000→3000, selector app: sockpuppetbrowser).

- [ ] **Step 5: Create deploy workflow**

`.forgejo/workflows/deploy-changedetection.yaml` — mirror `deploy-bentopdf.yaml`: trigger on `k3s-ha-cluster/changedetection/**`, checkout, kubeconfig from `KUBECONFIG_DEPLOY`, ensure namespace, apply `k3s-ha-cluster/changedetection/`, rollout status, ntfy notify to `homelab-deploys`.

- [ ] **Step 6: Apply locally and verify**

Run `kubectl apply -f k3s-ha-cluster/changedetection/`, then `kubectl -n changedetection rollout status deploy/changedetection --timeout=120s` and `kubectl -n changedetection rollout status deploy/sockpuppetbrowser`. Expected: both 1/1 Ready; `kubectl -n changedetection logs deploy/sockpuppetbrowser` shows a listening browser server.

- [ ] **Step 7: Commit**

```bash
git add k3s-ha-cluster/changedetection/ .forgejo/workflows/deploy-changedetection.yaml
git commit -m "feat(changedetection): deploy app + playwright stealth browser"
```

---

### Task 2: Expose via Caddy + DDNS

**Files:**
- Modify: `k3s-ha-cluster/caddy/configmap.yaml` (add route)
- Modify: `k3s-ha-cluster/ddns/config.json` (add subdomain)

**Interfaces:**
- Consumes: `changedetection.changedetection.svc.cluster.local:5000` from Task 1.

- [ ] **Step 1: Add Caddy route**

Append to the Caddyfile in `configmap.yaml`:

```caddyfile
changedetection.yukselcloud.com {
    log
    crowdsec
    reverse_proxy changedetection.changedetection.svc.cluster.local:5000 {
        header_up Host {host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-For {remote_host}
    }
}
```

- [ ] **Step 2: Add DDNS subdomain**

Add `{ "name": "changedetection", "proxied": false }` to the `subdomains` array in `ddns/config.json`.

- [ ] **Step 3: Commit (workflows auto-apply)**

```bash
git add k3s-ha-cluster/caddy/configmap.yaml k3s-ha-cluster/ddns/config.json
git commit -m "feat(changedetection): expose via Caddy + DDNS"
```

- [ ] **Step 4: Verify**

Wait for `caddy-upgrade` + `deploy-ddns` workflows to finish, then `curl -sS -o /dev/null -w '%{http_code}' https://changedetection.yukselcloud.com` → expect `200` (or 401 from the app login redirect, not a Caddy/CrowdSec block).

---

### Task 3: Configure ntfy notifications

**Files:**
- Modify: `k3s-ha-cluster/changedetection/README.md` (document apprise URL)
- Modify: `k3s-ha-cluster/ntfy/README.md` (add changedetection to the integrations table)

**Interfaces:**
- Consumes: ntfy token from Tay's local secret store; topic `homelab-changedetection`.

- [ ] **Step 1: Document the apprise URL**

In the changedetection README, record the exact per-watch notification URL:

```text
ntfys://tk_<NTFY_TOKEN>@ntfy.yukselcloud.com/homelab-changedetection?auth=token
```

with the note that the token is the existing `NTFY_TOKEN` repo secret value (never committed).

- [ ] **Step 2: Update ntfy integrations table**

Add row `| changedetection.io | homelab-changedetection | apprise URL in watch settings |` to `k3s-ha-cluster/ntfy/README.md`.

- [ ] **Step 3: Smoke-test the topic**

```bash
curl -H "Authorization: Bearer tk_<TOKEN>" -H "Title: test" -d "changedetection topic test" https://ntfy.yukselcloud.com/homelab-changedetection
```

Expected: ntfy receives it (verify in the ntfy UI/phone).

- [ ] **Step 4: Commit**

```bash
git add k3s-ha-cluster/changedetection/README.md k3s-ha-cluster/ntfy/README.md
git commit -m "docs(changedetection): document ntfy notification"
```

---

### Task 4: Cloudflare bypass strategy

**Files:**
- Modify: `k3s-ha-cluster/changedetection/README.md` (bypass notes)
- Modify: `k3s-ha-cluster/media/flaresolverr/values.yaml` (pin tag + deprecation comment) — optional, low risk

**Interfaces:** none new.

- [ ] **Step 1: Document the reality**

README section: FlareSolverr is unmaintained and does not solve Cloudflare Turnstile. changedetection's fetcher chain is: default non-JS fetcher → Playwright stealth (sockpuppetbrowser) for JS pages → BrowserSteps for login/interaction → residential proxy for hard-Turnstile sites. Record which of amazon.de / vatanbilgisayar.com / gigantti.fi need which.

- [ ] **Step 2: Pin FlareSolverr tag + deprecation note**

In `media/flaresolverr/values.yaml`, pin `tag: v3.3.21` (last known release) and add a comment that it is only kept for Prowlarr indexers, not used by changedetection.

- [ ] **Step 3: Commit**

```bash
git add k3s-ha-cluster/changedetection/README.md k3s-ha-cluster/media/flaresolverr/values.yaml
git commit -m "docs(changedetection): Cloudflare bypass strategy; pin flaresolverr"
```

---

### Task 5: End-to-end verification (Amazon.de RAM 64GB → ntfy)

**Files:** none (runtime verification only)

**Interfaces:**
- Consumes: Tasks 1–4 complete.

- [ ] **Step 1: Create the watch via API**

Use the changedetection REST API to add an amazon.de 64GB RAM product URL, with the ntfy apprise URL from Task 3 and price-tracking enabled.

- [ ] **Step 2: Confirm the price is fetched**

Check the watch's last-checked snapshot extracts the product price (not a Cloudflare challenge page). Expected: JSON-LD `offers.price` or visible price text present in the snapshot.

- [ ] **Step 3: Trigger a change and confirm ntfy**

Force a re-check; on a detected diff, confirm a message lands on `homelab-changedetection` with the diff.

- [ ] **Step 4: Record results**

Document in the changedetection README which sites were verified, which fetcher worked, and which still hit Turnstile (if any).
