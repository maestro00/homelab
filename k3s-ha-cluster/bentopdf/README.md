# BentoPDF

Privacy-first PDF toolkit, self-hosted. Fork of Stirling-PDF where **all
processing happens in the browser** via WASM. PDFs are never uploaded to the
cluster.

- **URL**: <https://bentopdf.yukselcloud.com>
- **Namespace**: `bentopdf`
- **Image**: `bentopdfteam/bentopdf-simple:v2.8.8` (Docker Hub)
- **Upstream**: <https://github.com/alam00000/bentopdf> (AGPL-3.0)

## Architecture

Caddy is the only ingress. Nothing is exposed on a MetalLB IP.

```text
Internet -> Caddy 192.168.0.201 -> Service bentopdf.bentopdf:80
         -> Pod bentopdf:8080 (nginx, unprivileged, 1 replica)
```

| File | Purpose |
| --- | --- |
| `deployment.yaml` | Deployment, 1 replica, port 8080 |
| `service.yaml` | ClusterIP Service, port 80 to targetPort 8080 |

## What it deliberately does not have

| Concern | Needed? | Why |
| --- | --- | --- |
| PVC / Longhorn volume | No | Static SPA, writes nothing to disk |
| MetalLB IP | No | Reached only through Caddy |
| Secrets | No | No credentials, no API keys |
| Database | No | Upstream confirms there is no DB |
| `securityContext` | No | Image already runs as non-root nginx, uid 101 |
| Replicas > 1 | No | Serves identical static files |

## Cross-origin isolation

Office conversion (LibreOffice WASM) and OCR need `SharedArrayBuffer`, which
only works on a secure, cross-origin isolated page. The image already ships the
required headers, so Caddy needs no header block:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

> `credentialless` is used rather than `require-corp` because it does not force
> CORP headers onto every subresource. HTTPS is mandatory: plain
> `http://192.168.x.x` will not work at all.

Verify through the proxy after any change:

```bash
curl -sSI https://bentopdf.yukselcloud.com \
  | grep -iE 'cross-origin-opener|cross-origin-embedder'
```

## Deploys

`.forgejo/workflows/deploy-bentopdf.yaml` applies both manifests on push to
those two files only, then notifies via ntfy. Also runs on
`workflow_dispatch`.

## Upgrades

Manual. Bump the tag in `deployment.yaml`, commit, push. The workflow deploys
it.

> The tag is deliberately pinned. The path filter does not retrigger on image
> changes, so a rolling tag like `:latest` would silently never update. Note
> that `ghcr.io/alam00000/bentopdf-simple` only publishes v1.x tags, while
> GitHub releases are on v2.x — Docker Hub is the registry with real version
> tags.

To mirror upstream into the Forgejo registry later, copy the skopeo pattern
from `update-opengym.yml`. Not needed today: the image is public.
