# changedetection.io

Self-hosted website change and price monitoring. Detects price and stock
changes on watched pages and pushes alerts to ntfy.

## Architecture

Two Deployments in the `changedetection` namespace:

| Component          | Port | Purpose                        |
| ------------------ | ---- | ------------------------------ |
| changedetection    | 5000 | App + built-in non-JS fetcher  |
| sockpuppetbrowser  | 3000 | Playwright stealth Chrome      |

Images:

- changedetection: `ghcr.io/dgtlmoon/changedetection.io:0.60.10`
- sockpuppetbrowser: `dgtlmoon/sockpuppetbrowser:0.0.3`

changedetection reaches the browser via
`PLAYWRIGHT_DRIVER_URL=ws://sockpuppetbrowser.changedetection.svc.cluster.local:3000/?stealth=1`.

Persistent data lives in the `changedetection-datastore` Longhorn PVC (5Gi,
mounted at `/datastore`). The web UI is served through Caddy at
`changedetection.yukselcloud.com` (ClusterIP service, no MetalLB IP).

## Deployment

```bash
kubectl apply -f k3s-ha-cluster/changedetection/
```

The `.forgejo/workflows/deploy-changedetection.yaml` workflow applies the
manifests on push to `master` and on manual dispatch.

## Secrets

`changedetection-secret` holds `salted-pass` (the web-UI password, stored as a
PBKDF2 salted hash). The real value lives in the cluster only; the committed
`secret.yaml` is a placeholder and the deploy workflow applies it
create-if-missing.

Generate a salted pass:

```bash
python3 - <<'PY'
import os, base64, hashlib
salt = os.urandom(32)
key = hashlib.pbkdf2_hmac('sha256', b'yourpassword', salt, 100000)
print(base64.b64encode(salt + key).decode())
PY
```

## Access

- URL: `https://changedetection.yukselcloud.com`
- Auth: single password (no username), from the salted pass above.

## Notifications

Per-watch apprise URL (ntfy):

```text
ntfys://tk_<NTFY_TOKEN>@ntfy.yukselcloud.com/homelab-changedetection?auth=token
```

`?auth=token` is required. This ntfy server uses bearer tokens, and apprise
otherwise falls back to basic auth. The token is the existing `NTFY_TOKEN`
Forgejo secret value, never committed.

## Cloudflare and bot protection

See issue #74 for the full strategy. Summary:

- FlareSolverr (media ns, v3.5.x) is an HTTP API for the arr stack indexers,
  not a changedetection fetcher; it stays wired to Prowlarr only.
- Use the Playwright fetcher (`sockpuppetbrowser`) for JS-heavy or lightly
  protected pages.
- Neither FlareSolverr nor Playwright stealth solves an interactive Turnstile
  (the click/human-verify captcha); for those use Browser Steps or a
  residential proxy.
