# Add a Service to Caddy with Correct Domain Name

## Overview

Exposing a new service publicly = add a Caddy route + a DDNS subdomain. Both
are now automated via Forgejo Actions on push to `master`.

## Steps

### 1. Add the Caddy route

Edit `k3s-ha-cluster/caddy/configmap.yaml` and add a site block:

```caddyfile
service.yukselcloud.com {
    log
    crowdsec
    reverse_proxy <svc>.<ns>.svc.cluster.local:<port>
}
```

`.forgejo/workflows/caddy-upgrade.yml` applies the ConfigMap + restarts Caddy
automatically (triggered on changes to `configmap.yaml`, or via
`workflow_dispatch`). No manual steps.

### 2. Add the DDNS subdomain

Edit `k3s-ha-cluster/ddns/config.json` and add a `subdomains` entry:

```json
{ "name": "service", "proxied": false }
```

`.forgejo/workflows/deploy-ddns.yml` renders the `config-cloudflare-ddns`
Secret from this template (the Cloudflare API token comes from the Forgejo
secret `CLOUDFLARE_DDNS_API_TOKEN`), applies it, and restarts the DDNS pod.
Triggered on changes to `k3s-ha-cluster/ddns/**`, or via `workflow_dispatch`.

### 3. Push

Push both changes to `master`. The workflows handle apply + rollout restart.

## Notes

- The API token is **never** in git. `temp/config.json` is gitignored and only
  kept locally; the source of truth is `k3s-ha-cluster/ddns/config.json`
  (template) + the Forgejo secret `CLOUDFLARE_DDNS_API_TOKEN`.
- `temp/config.json` is also used locally to manually refresh
  `config-cloudflare-ddns-Secret.yaml` if you need to deploy outside the
  workflow:

  ```bash
  kubectl -n ddns create secret generic config-cloudflare-ddns \
      --from-file=config.json=temp/config.json \
      --dry-run=client -oyaml | kubectl -n ddns apply -f -
  kubectl -n ddns rollout restart deploy cloudflare-ddns
  ```
