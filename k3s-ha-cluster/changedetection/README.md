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

## Verified end-to-end (2026-11-02)

Tested against `https://www.amazon.de/dp/B0DSR14511` (Crucial Pro DDR5 64GB
6400MHz). The Playwright stealth fetcher retrieved the real product page
(title, 1.5MB screenshot, price in the DOM) with no Cloudflare captcha, and a
forced change produced an ntfy alert on `homelab-changedetection`.

## Adding a price watch

Via the REST API (API key in the datastore, see `changedetection.json`):

```bash
curl -X POST https://changedetection.yukselcloud.com/api/v1/watch \
  -H "x-api-key: <API_KEY>" -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.amazon.de/dp/ASIN",
    "fetch_backend": "html_webdriver",
    "notification_urls": ["ntfys://tk_<TOKEN>@ntfy.yukselcloud.com/homelab-changedetection?auth=token"]
  }'
```

For a clean price-only watch, use the Visual Selector in the UI (works because
Playwright is enabled) to pick the price element, or add a CSS
`include_filters` entry. Amazon.de does not always expose price in JSON-LD, so
a CSS selector on the buybox is more reliable than the restock processor.

### Track only the price (include_filters)

`include_filters` is a list of CSS selectors; only matching elements are kept
in the snapshot, so the change diff shows just those values. Verified on
Amazon.de — `.a-price .a-offscreen` collapses a 666 KB page to a 119-byte list
of prices:

```json
{
  "include_filters": [".a-price .a-offscreen"]
}
```

For the single buybox price, prefer the Visual Selector, or a tighter selector
such as `#corePriceDisplay_desktop_feature_div .a-offscreen`.

> Amazon.de caveat: if the item doesn't ship to your delivery country, the
> buybox shows "similar items" instead of a direct price, so a single clean
> price may not be present in the page at all.
