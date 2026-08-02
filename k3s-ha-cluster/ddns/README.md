# DDNS (Cloudflare)

Keeps `yukselcloud.com` DNS records pointed at your home IP. Runs
`timothyjmiller/cloudflare-ddns` in the `ddns` namespace.

## Files

| File              | Purpose                          |
| ----------------- | -------------------------------- |
| `config.json`     | Cloudflare zone + subdomain list |
| `deployment.yaml` | Deployment + mounts ddns Secret  |

## Adding a subdomain for a new service

1. Add the subdomain to the `subdomains` list in `config.json`.
2. Push. `.forgejo/workflows/deploy-ddns.yml` renders the real Secret from the
   `CLOUDFLARE_DDNS_API_TOKEN` Forgejo secret, applies it, and restarts the pod.

> The Cloudflare API token is **never** in git — `config.json` only holds the
> placeholder. `temp/config.json` (gitignored) keeps a local working copy.

See
[`.kiro/skills/homelab-k3s/references/add-service-to-caddy.md`](../../.kiro/skills/homelab-k3s/references/add-service-to-caddy.md)
for the full "expose a new service" flow (Caddy route + DDNS subdomain).
