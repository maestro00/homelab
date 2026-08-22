# openGym deployment

Self-hosted gym and body-weight tracker: plan routines, log workouts, track
weight and progress. Passkey login, PWA. AGPL-3.0.

Upstream: <https://gitea.com/DuarteSantos/openGym> (GitHub mirror:
DuarteSantos8/openGym). Issue: #49.

## Architecture

Single pod, two containers sharing one Longhorn PVC (`opengym-data`):

| Container | Image                                     | Role                                            |
| --------- | ----------------------------------------- | ----------------------------------------------- |
| media     | `alpine/git` (init container)             | One-time download of exercise images (~140 MB)  |
| api       | `git.yukselcloud.com/lab/opengym-api`     | Node backend, passkeys, JSON data in `/data`    |
| web       | `git.yukselcloud.com/lab/opengym-web`     | nginx serving React build, proxies `/api`       |

Images are built from the upstream source with podman and pushed to the local
Forgejo registry (pinned to `v1.2.7`) — no dependency on upstream ghcr.
The `forgejo-registry` pull secret must exist in the namespace (copied from
`ntfy`).

PVC layout via subPaths:

- `data/` — users, passkeys, per-user state, session secret, VAPID keys
- `media/img/`, `media/gif/` — exercise dataset served read-only by nginx

## Environment

| Variable   | Value                        | Purpose                             |
| ---------- | ---------------------------- | ----------------------------------- |
| RP_ID      | opengym.yukselcloud.com      | Passkey hostname binding            |
| ORIGIN     | <https://opengym.yukselcloud.com> | Full URL; sessions/WebAuthn      |
| RP_NAME    | openGym                      | Display name in passkey prompts     |
| DATA_DIR   | /data                        | JSON storage root                   |

Optional toggles (admin dashboard, invite-only signup) are documented in the
upstream `.env.example`; none are enabled yet.

> Passkeys only work at the exact `RP_ID` over HTTPS. Until the service is
> exposed through Caddy, use guest mode over an HTTP port-forward.

## Deployment

```bash
kubectl create ns opengym            # if missing
kubectl apply -f k3s-ha-cluster/opengym/
```

First start clones the exercise dataset into the PVC (~140 MB); later restarts
skip the download.

## Accessing the application

Exposed at <https://opengym.yukselcloud.com> via Caddy with CrowdSec
protection. Passkey login works there (HTTPS + matching `RP_ID`).

## Exposure

Wired through the standard two-file flow:

- Route block `opengym.yukselcloud.com` in
  `k3s-ha-cluster/caddy/configmap.yaml`
  (reverse_proxy -> `opengym.opengym.svc.cluster.local:80`)
- `{ "name": "opengym", "proxied": false }` in the subdomains list of
  `k3s-ha-cluster/ddns/config.json`

Push to master; the caddy-upgrade and deploy-ddns workflows apply both.

For cluster-local debugging without DNS:

```bash
kubectl -n opengym port-forward svc/opengym 8080:80
```

## Upgrading

Rebuild + push both images with a new tag, bump the tags in
`deployment.yaml`, re-apply:

```bash
podman build -t git.yukselcloud.com/lab/opengym-api:vX.Y.Z \
    --build-arg VERSION=vX.Y.Z /tmp/opencode/opengym-src/api
podman build -t git.yukselcloud.com/lab/opengym-web:vX.Y.Z \
    --build-arg VERSION=vX.Y.Z -f web/Dockerfile .
podman push git.yukselcloud.com/lab/opengym-api:vX.Y.Z
podman push git.yukselcloud.com/lab/opengym-web:vX.Y.Z
```

Data is plain JSON in `/data` — back up the `opengym-data` PVC (Longhorn
snapshot suffices).
