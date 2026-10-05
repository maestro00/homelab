# BentoPDF integration plan considerations

Findings gathered 2026-10-04, before any implementation. Nothing in this
folder is deployed yet.

> This is a planning document. It records what was investigated and what
> still needs a decision. It is not a deployment guide.

## What BentoPDF is

A privacy-first PDF toolkit that runs **entirely in the browser**. It is a
fork of Stirling-PDF. All PDF processing happens client-side via WASM, so
files are never uploaded to the server.

## Research findings

### Two builds exist, pick the self-hosted one

| Image                                      | Use                |
| ------------------------------------------ | ------------------ |
| `ghcr.io/alam00000/bentopdf-simple:latest` | Self-hosted build. |
| `ghcr.io/alam00000/bentopdf:latest`        | Commercial build.  |

The commercial build powers bentopdf.com and is meant for license holders.
Upstream guidance is explicit: *"If in doubt, pull the Self-Hosted build."*
The `-simple` image is **not** a feature-reduced lite version — every PDF
tool is present.

### No Helm chart exists

Nothing maintained upstream, so raw manifests are the correct choice. This
matches the existing `opengym` and `portfolio` layout in this repo rather
than inventing a custom chart.

### No state, which removes most of the usual machinery

| Concern               | Needed? | Why                               |
| --------------------- | ------- | --------------------------------- |
| PVC / Longhorn volume | No      | Static site, no files written.    |
| MetalLB IP            | No      | Reached through Caddy only.       |
| Secrets               | No      | No credentials, no API keys.      |
| Database              | No      | Upstream confirms there is no DB. |
| Replicas > 1          | No      | Serves identical static files.    |

This is the single biggest simplification versus a typical service in this
cluster.

### Resource requirements

Upstream minimums are 512 MB RAM and roughly 100 MB storage, CPU
unconstrained. Requests can stay well below the limits.

### Port

Listens on **8080** inside the container, served by
`nginx-unprivileged`. The container already runs as non-root, so no
privileged port and no extra capability is needed.

## The one hard constraint: cross-origin isolation

Office-file conversion (LibreOffice WASM) requires `SharedArrayBuffer`. That
only works when the page is:

1. served from a **secure context** (HTTPS, satisfied by Caddy), and
2. **cross-origin isolated**, which needs both of these response headers:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The official image already sends these headers, but they must survive the
reverse proxy, so they are set explicitly in the Caddy route per the
upstream Caddy example.

> Under `require-corp`, every subresource must be same-origin or
> CORS-enabled. This is the main technical risk in the integration: OCR and
> Office tools may fail through the proxy even though the UI loads fine. It
> is a **test item**, not a design decision, and it can only be confirmed
> after deploying. Plain `http://192.168.x.x` will not work at all — HTTPS
> is mandatory, not a nice-to-have.

## Existing state in this cluster

### Nothing to migrate

No `bentopdf` or `stirlingpdf` references exist in the repo outside a
scratch file, and no PDF workload is deployed. This is a **new service**.

### Orphan DNS records

These exist in Cloudflare but are not managed by
`ddns/config.json`. They all point at `85.156.79.45`, which is **not** this
cluster's public IP (`91.154.86.240`):

```text
changedetection  demo       homarr
keycloak         nextcloud  paperless
stirlingpdf
```

They are leftovers and currently resolve nowhere useful. Clean them up
separately; `homarr` is the most obviously dead now that the namespace is
gone.

> A separate finding from the same investigation: `ldap.yukselcloud.com`
> does not resolve at all. The record points at the private address
> `192.168.0.205`, written by `external-dns` from a stale
> `external-dns.alpha.kubernetes.io/hostname` annotation on the `lldap`
> Service, which fights the `cloudflare-ddns` updater every 60 seconds.
> Unrelated to BentoPDF, still unfixed.

### Repo conventions to follow

- Raw manifests in `k3s-ha-cluster/<service>/`, mirroring `opengym`.
- New namespace named after the service, `ClusterIP` Service only.
- Caddy route with `log` and `crowdsec`, then `reverse_proxy`.
- Subdomain added to `ddns/config.json` so the DDNS updater owns it.
- A `.forgejo/workflows/deploy-bentopdf.yml` with an ntfy notify step.

## Proposed defaults

Awaiting approval. Listed so they can be corrected in one pass.

1. **Image**: `ghcr.io/alam00000/bentopdf-simple:latest`, mirrored into
   `git.yukselcloud.com/lab/bentopdf-simple:v<version>` with `skopeo` and
   pinned there, following the `opengym` update workflow.
2. **Layout**: raw manifests in `k3s-ha-cluster/bentopdf/`, namespace
   `bentopdf`, `ClusterIP` Service, replicas 1.
3. **Subdomain**: `pdf.yukselcloud.com`.
4. **Caddy route**: `log`, `crowdsec`, `reverse_proxy`, plus explicit COOP
   and COEP headers.
5. **Homepage**: a widget in the tools group.
6. **Workflow**: `deploy-bentopdf.yml` applying the manifests, restarting on
   ConfigMap changes and notifying via ntfy.

## Open decision: auth posture

Not yet decided. This is a judgement call about exposure, not a technical
constraint, so it is not being defaulted.

| Concern           | Authelia-gated        | Public               |
| ----------------- | --------------------- | -------------------- |
| Who can use it    | you and `group:infra` | anyone with the URL  |
| CPU and RAM abuse | only you              | open to the internet |
| Caddy route       | `forward_auth`        | `reverse_proxy`      |
| UX                | extra click           | instant              |

The gated route reuses your existing session cookie, so there is no second
login.

**Recommendation: gate it.** PDFs never leave the browser either way, so
gating costs no privacy. It only shields the cluster from anonymous
resource burn, and `home.yukselcloud.com` already proves the pattern works
after the redirect fix in `dad9ae6` and `79565ab`.

### If gated, two traps to avoid

Both were hit for real while protecting `home.yukselcloud.com`:

- Authelia v4.39 made authz endpoints **opt-in**. Without
  `server.endpoints.authz.forward-auth` the endpoint returns 404 and Caddy
  passes that 404 straight through, so the site looks broken rather than
  locked. It is already enabled in `auth/authelia/values.yaml`.
- The authelia chart **overrides** `session.cookies[].authelia_url`,
  computing it from `subdomain` plus `domain`. Setting `authelia_url`
  directly in values is silently ignored. Do not also set
  `default_redirection_url` to the same value; Authelia refuses to start.

## Verification checklist

After deploying:

```bash
# serves over HTTPS
curl -s -o /dev/null -w '%{http_code}\n' https://pdf.yukselcloud.com

# cross-origin isolation headers survive the proxy
curl -sI https://pdf.yukselcloud.com \
  | grep -iE 'cross-origin-opener|cross-origin-embedder'

# DNS resolves to the cluster, not a private address
dig +short @1.1.1.1 pdf.yukselcloud.com A
```

Then confirm in the browser that the page reports itself cross-origin
isolated, and exercise one Office-file conversion and one OCR job. Those two
are the real test; everything else can pass while they are broken.

## Reference

- Self-hosting guide: <https://www.bentopdf.com/docs/self-hosting>
- Docker notes and Caddy example:
  <https://bentopdf.com/docs/self-hosting/docker>
