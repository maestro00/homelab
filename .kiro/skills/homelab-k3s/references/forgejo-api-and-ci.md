# Forgejo API and CI reference

How to work with Forgejo programmatically: API access, tokens, the GitOps
workflow inventory, and the container registry pattern.

## Instance facts

- URL: `https://git.yukselcloud.com` (Forgejo 14.0.1, gitea-1.22 compatible)
- Primary repo: `lab/homelab` (origin), GitHub mirror `maestro00/homelab`
- Runner: self-hosted, pod `forgejo-runner` in namespace `forgejo`
- Runner image: `git.yukselcloud.com/lab/kubectl-node:latest`

## API access

Base URL for all calls:

```text
https://git.yukselcloud.com/api/v1
```

Authenticate every request with the lab user's token:

```bash
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  "https://git.yukselcloud.com/api/v1/repos/lab/homelab/issues?state=open"
```

> The token value never goes into git or skill files. It lives in Tay's local
> secret store (`.env`, gitignored). Ask Tay or read it from there when needed;
`$FORGEJO_TOKEN` above is a placeholder.

Common operations:

| Task | Call |
| ---- | ---- |
| List open issues | `GET /repos/lab/homelab/issues?state=open&type=issues` |
| Create issue | `POST /repos/lab/homelab/issues` body `{"title","body"}` |
| Comment | `POST /repos/lab/homelab/issues/{n}/comments` body `{"body"}` |
| Close/reopen | `PATCH /repos/lab/homelab/issues/{n}` body `{"state"}` |
| List workflow runs | `GET /repos/lab/homelab/actions/tasks` |
| List container packages | `GET /packages/lab?type=container` |

JSON bodies are easiest to build safely with `jq -n --rawfile`:

```bash
jq -n --rawfile b issue.md '{body:$b}' > payload.json
```

## Workflow inventory (GitOps CI)

All workflows live in `.forgejo/workflows/` and trigger on push to master.
Every service folder should have a matching workflow; use path filters so
unrelated pushes do not redeploy everything.

| File | Trigger paths | Action |
| -------------------- | -------------------------------------- | ----------------------------------- |
| `caddy-upgrade.yml`  | `k3s-ha-cluster/caddy/configmap.yaml`  | apply ConfigMap + restart Caddy     |
| `deploy-ddns.yml`    | `k3s-ha-cluster/ddns/**`               | render Secret from Forgejo secret `CLOUDFLARE_DDNS_API_TOKEN`, apply, restart pod |
| `homer-deploy.yml`   | `k3s-ha-cluster/homer/config.yaml`     | apply Homer config                  |
| `deploy-beszel.yml`  | `k3s-ha-cluster/monitoring/beszel/**`  | deploy beszel                       |
| `deploy-portfolio.yaml` | `k3s-ha-cluster/portfolio/**`       | deploy portfolio                    |
| `test.yml`           | every push                             | smoke test                          |

Most also accept `workflow_dispatch:` for manual runs.

Secrets used by workflows are **Forgejo repo secrets** (never git): the
workflow renders them into Kubernetes Secrets at apply time. Pattern example:
`deploy-ddns.yml` substitutes `CLOUDFLARE_DDNS_API_TOKEN` into the
`config-cloudflare-ddns` Secret. Repo manifests only ever contain a
placeholder like `__CLOUDFLARE_API_TOKEN__`.

Verify a push triggered what you expect:

```bash
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  "https://git.yukselcloud.com/api/v1/repos/lab/homelab/actions/tasks" \
  | jq -r '.workflow_runs[:5][] | "\(.name) | \(.status) | \(.head_sha[:7])"'
```

## Container registry

Forgejo's built-in registry serves images at
`git.yukselcloud.com/<owner>/<name>:<tag>` (owner is usually `lab`). Used for
self-built images so deployments do not depend on upstream registries.

Build and push from the local machine (podman or docker):

```bash
podman build -t git.yukselcloud.com/lab/opengym-api:v1.2.7 ./api
podman login git.yukselcloud.com -u lab -p "$FORGEJO_TOKEN"
podman push git.yukselcloud.com/lab/opengym-api:v1.2.7
```

Pulling private packages from the cluster needs the `forgejo-registry`
imagePullSecret (`kubernetes.io/dockerconfigjson`). It exists once per
namespace that needs it; copy it instead of recreating:

```bash
kubectl -n ntfy get secret forgejo-registry -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,
            .metadata.resourceVersion,.metadata.creationTimestamp,
            .metadata.annotations)
        | .metadata.namespace="<target-ns>"' \
  | kubectl apply -f -
```

Reference the secret in the pod spec:

```yaml
spec:
  imagePullSecrets:
    - name: forgejo-registry
```

> Forgejo 14.0.1 has no package-visibility API endpoint. Packages are private;
use the pull secret rather than trying to flip visibility via API. Pin image
tags to versions, never `:latest`.
