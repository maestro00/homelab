# BentoPDF onboarding plan

Approach **A** (approved): raw manifests, not the upstream Helm chart.

Deploy BentoPDF (privacy-first, fully client-side PDF toolkit) to the
`bentopdf` namespace, expose it at `bentopdf.yukselcloud.com` through Caddy.

## Why not the upstream chart

- The chart lives only in the upstream git repo (`chart/`, v1.0.7) — no Helm
  repo, no OCI registry, no release tarball. `helm install` means cloning
  GitHub inside the runner on every deploy.
- Its default image tag is broken: `image.tag: ''` falls back to
  `.Chart.AppVersion` = `2.8.8`, and no such tag exists on ghcr.
- Most of what the chart templates (Ingress, Gateway API, HTTP routes) targets
  ingress controllers this cluster does not run — Caddy handles ingress from
  the Caddyfile.
- BentoPDF is static nginx serving a pre-built SPA: no DB, no PVC, no secrets.
  A chart has nothing to configure.

## Verified upstream facts

| Fact | Value |
| --- | --- |
| Image | `bentopdfteam/bentopdf-simple:v2.8.8` (Docker Hub) |
| Port | `8080` (`PORT=8080` baked into the image) |
| Runs as | `nginx` (uid 101), unprivileged nginx, entrypoint `/docker-entrypoint.sh` |
| Persistence | none, all processing happens in the browser |
| COOP/COEP | shipped by the image (`same-origin` / `credentialless`), so SharedArrayBuffer works through Caddy with no extra headers |
| Upstream | <https://github.com/alam00000/bentopdf> (AGPL-3.0) |

Use Docker Hub, not ghcr: `ghcr.io/alam00000/bentopdf-simple` only has v1.x
tags (`v1.15.4` newest), while GitHub releases are `v2.8.8`. Docker Hub is the
registry with real version tags. Keep `:latest` out of git — the deploy
workflow path filter does not retrigger on image changes, so a rolling tag
would silently never update.

## Cluster conventions to follow

Recent services (`opengym`, `portfolio`, `homepage`, `ntfy`) all use:

- **ClusterIP** Service, no MetalLB IP — Caddy is the only ingress
- namespace created by the workflow (`Ensure Namespace` step pattern)
- 2-space YAML indent, quoted memory values, explicit `resources`
  requests/limits, HTTP probes on `/`
- Caddy site block with `log` + `crowdsec` + `reverse_proxy`
- DDNS subdomain entry in `k3s-ha-cluster/ddns/config.json`
- a Forgejo workflow with `ntfy` notify on completion

## Files

Create:

- `k3s-ha-cluster/bentopdf/deployment.yaml` — 1 replica, port 8080,
  resources, liveness/readiness probes on `/`, no volumes, no securityContext
  (image is already non-root and the container FS is writable, so nginx's
  cache/run dirs work without `emptyDir` mounts)
- `k3s-ha-cluster/bentopdf/service.yaml` — ClusterIP, port 80 → targetPort
  8080
- `.forgejo/workflows/deploy-bentopdf.yaml` — Ensure Namespace, apply, rollout
  status, ntfy notify. Path filter on the two manifest files explicitly (not
  `bentopdf/**`) so commits touching this plan file do not trigger a deploy
- `k3s-ha-cluster/bentopdf/README.md` — architecture, exposure, upgrades

Modify:

- `k3s-ha-cluster/caddy/configmap.yaml` — append the `bentopdf` site block
  after the `opengym` block
- `k3s-ha-cluster/ddns/config.json` — add `bentopdf` to `subdomains`

Deploy order matters: DNS must resolve before the Caddy route lands, otherwise
ACME cannot issue the certificate and the first `curl` fails on TLS.

## Steps

1. **Manifests.** Create namespace, write both manifests, validate with
   `kubectl apply --dry-run=server -f k3s-ha-cluster/bentopdf/`, then apply.
   Verify: `kubectl -n bentopdf rollout status deploy/bentopdf` and an
   in-cluster `curl` against `http://bentopdf:80/` expecting `200`.
   Commit and push.

2. **DNS.** Add the subdomain entry to `ddns/config.json`, `jq empty` it to
   validate the JSON, commit, push. The `deploy-ddns` workflow applies and
   restarts the DDNS pod. Verify: `dig +short bentopdf.yukselcloud.com`
   eventually returns the public IP (`ntfy.yukselcloud.com` returns
   `91.154.86.240` today).

3. **Caddy route.** Append the site block, commit, push. The `caddy-upgrade`
   workflow applies the ConfigMap and restarts Caddy. Verify the config is
   valid before trusting the restart:
   `kubectl -n caddy exec deploy/caddy -- caddy validate --config /etc/caddy/Caddyfile`
   (prints `Valid configuration`), then
   `curl -sSI https://bentopdf.yukselcloud.com` expecting `200` and
   `curl -sSI https://bentopdf.yukselcloud.com | grep -i cross-origin`
   expecting the COOP/COEP headers.

4. **Workflow.** Create `.forgejo/workflows/deploy-bentopdf.yaml`, trigger it
   via `POST /repos/lab/homelab/actions/workflows/deploy-bentopdf.yaml/dispatches`
   with body `{"ref":"master"}` (token: the `forgejo_admin_token` value from
   the local `.env`, gitignored — never commit it). Verify the run reports
   success and the ntfy notification arrives.

5. **Wrap up.** Write the README, post a summary comment on Forgejo issue
   `#48`, close it.

## Notes and limits

- No PVC, no backup, no MetalLB IP. There is no state to lose.
- Upgrades are manual: bump the tag in `deployment.yaml`, commit, push. The
  workflow deploys it. If mirroring upstream into the Forgejo registry with
  skopeo is wanted later, copy the `update-opengym.yml` pattern.
- Optional, not in scope: a tile in the homepage dashboard
  (`k3s-ha-cluster/homepage/values.yaml`, `services:` list) and an Authelia
  access rule if the site should be private.
