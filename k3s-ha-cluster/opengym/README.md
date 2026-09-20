# openGym deployment

Self-hosted gym and body-weight tracker: plan routines, log workouts, track
weight and progress. Passkey login, PWA. AGPL-3.0.

Upstream: <https://github.com/DuarteSantos8/openGym>

## Architecture

Single pod, two containers sharing one Longhorn PVC (`opengym-data`):

| Container | Image                                     | Role                                            |
| --------- | ----------------------------------------- | ----------------------------------------------- |
| media     | `alpine/git` (init container)             | One-time download of exercise images (~140 MB)  |
| api       | `git.yukselcloud.com/lab/opengym-api`     | Node backend, passkeys, JSON data in `/data`    |
| web       | `git.yukselcloud.com/lab/opengym-web`     | nginx serving React build, proxies `/api`       |

Images are upstream's prebuilt `ghcr.io/DuarteSantos8/opengym-{api,web}`
(zero building), archived into the local Forgejo registry pinned at the
released version (`vX.Y.Z`) — the cluster always pulls immutable version tags
from `git.yukselcloud.com`, not a rolling `:latest`. The `forgejo-registry`
pull secret must exist in the namespace (copied from `ntfy`).

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

Automated via Forgejo workflow `update-opengym.yml` — trigger from the
Actions tab with an optional version tag (leave empty for latest).

The workflow resolves the latest upstream release from GitHub, copies both
images from `ghcr.io` (`:latest`) into the Forgejo registry pinned at
`vX.Y.Z` with skopeo (nothing is built), updates `deployment.yaml`, commits,
applies the manifests and rolling-restarts the deployment.

Manual upgrade (same thing, local machine):

```bash
# archive upstream's prebuilt image into the Forgejo registry
skopeo copy docker://ghcr.io/DuarteSantos8/opengym-api:vX.Y.Z \
    docker://git.yukselcloud.com/lab/opengym-api:vX.Y.Z
skopeo copy docker://ghcr.io/DuarteSantos8/opengym-web:vX.Y.Z \
    docker://git.yukselcloud.com/lab/opengym-web:vX.Y.Z

# bump tags in deployment.yaml and apply
sed -i "s/opengym-api:v[0-9.]*/opengym-api:vX.Y.Z/" k3s-ha-cluster/opengym/deployment.yaml
sed -i "s/opengym-web:v[0-9.]*/opengym-web:vX.Y.Z/" k3s-ha-cluster/opengym/deployment.yaml
kubectl -n opengym apply -f k3s-ha-cluster/opengym/
kubectl -n opengym rollout restart deploy opengym
```

> `ghcr.io/DuarteSantos8/opengym-{api,web}` only carries a rolling `:latest`
> tag, not `vX.Y.Z` — the workflow copies `:latest` and re-tags it with the
> released version, so the pin lives only in our registry.

Data is plain JSON in `/data` — back up the `opengym-data` PVC (Longhorn
snapshot suffices).

### Runner note

The workflow runs in the `kubectl-node` container, which ships `jq` and
`skopeo` (plus kubectl, git, curl). No Docker daemon or build capability is
needed — skopeo only reads from ghcr and writes to the Forgejo registry.
