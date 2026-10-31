# Portfolio

Static personal portfolio site served by nginx, deployed on K3s.

## Overview

The portfolio is a single-page static site stored in ConfigMaps and served by
nginx pods. Caddy handles TLS termination and routes
`portfolio.yukselcloud.com` to the `portfolio-service`.

The page's subject is the cluster that serves it: its content, photographs and
the deploy-pipeline frame are all real pieces of this homelab.

## Files

| File | Purpose |
| ------ | --------- |
| `html/index.html` | Page source (gitignored; local truth) |
| `img/` | Photographs mounted at `/img` (gitignored; local truth) |
| `deploy.sh` | Regenerates both committed manifests from `html/` + `img/` |
| `configmap.yaml` | Page content (`portfolio-html`) mounted into nginx |
| `assets-configmap.yaml` | Photographs (`portfolio-assets`, binaryData) |
| `deployment.yaml` | 2-replica nginx deployment (`portfolio-site`) |
| `service.yaml` | ClusterIP service (`portfolio-service`) targeted by Caddy |
| `pod.yaml` | One-off debug pod for quick local testing |

## Update content

1. Edit `html/index.html` and/or files in `img/`.
2. Run `./deploy.sh` — it rewrites `configmap.yaml` and
   `assets-configmap.yaml` and fails if either exceeds the 1 MiB ConfigMap
   budget.
3. Commit both manifests. A push touching this directory triggers the
   `deploy-portfolio` Forgejo workflow (apply + rollout restart + wait).

Local preview: `html/` can be opened directly; for a faithful run copy `img/`
into `html/img/` first (that mirror is never committed).

## Deploy (first time)

```bash
kubectl create namespace portfolio

kubectl -n portfolio apply -f configmap.yaml
kubectl -n portfolio apply -f assets-configmap.yaml
kubectl -n portfolio apply -f deployment.yaml
kubectl -n portfolio apply -f service.yaml
```

## Rollback

`git revert` the manifest commit and push — the same workflow redeploys the
previous page.
