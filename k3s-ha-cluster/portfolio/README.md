# Portfolio

Static personal portfolio site served by nginx, deployed on K3s.

## Overview

The portfolio is a single-page static site stored in a ConfigMap and served
by nginx pods. Caddy handles TLS termination and routes
`demo.yukselcloud.com` to the `portfolio-service`.

## Files

| File | Purpose |
| ------ | --------- |
| `configmap.yaml` | HTML content (`portfolio-html`) mounted into nginx |
| `deployment.yaml` | 2-replica nginx deployment (`portfolio-site`) |
| `service.yaml` | ClusterIP service (`portfolio-service`) targeted by Caddy |
| `pod.yaml` | One-off debug pod for quick local testing |
| `html/` | Local HTML source (gitignored, built into ConfigMap) |

## Deploy

```bash
kubectl create namespace portfolio   # first time only

kubectl -n portfolio apply -f configmap.yaml
kubectl -n portfolio apply -f deployment.yaml
kubectl -n portfolio apply -f service.yaml
```

## Update content

Edit the HTML in `configmap.yaml` (or regenerate it from `html/`), then:

```bash
kubectl -n portfolio apply -f configmap.yaml
kubectl -n portfolio rollout restart deployment/portfolio-site
kubectl -n portfolio rollout status deployment/portfolio-site --timeout=90s
```

The Forgejo workflow (`.forgejo/workflows/deploy-portfolio.yaml`) handles this
automatically on every push to `k3s-ha-cluster/portfolio/**`.

## Caddy routing

```caddyfile
demo.yukselcloud.com {
    reverse_proxy portfolio-service.portfolio.svc.cluster.local:80
}
```

See `../caddy/configmap.yaml` for the full Caddyfile.
