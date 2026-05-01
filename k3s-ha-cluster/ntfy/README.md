# ntfy

Self-hosted push notification server. Deployed as a custom Helm chart in the `ntfy`
namespace, exposed via Caddy at `ntfy.yukselcloud.com`.

## Prerequisites

Fill in `secret.yaml` before deploying:

1. **Generate a bcrypt hash**:

   ```bash
   htpasswd -bnBC 10 "" yourpassword | tr -d ':\n' | sed 's/\$2y\$/\$2a\$/'
   ```

2. **Generate a token** (must be exactly 32 chars, `tk_` prefix):

   ```bash
   echo "tk_$(openssl rand -hex 20 | head -c 29)"
   ```

3. **Fill `secret.yaml`** directly — no base64 needed with `stringData`:

   ```yaml
   auth-users: "lab:$2a$10$YOURHASH:admin"
   auth-tokens: "lab:tk_YOURTOKEN:homelab"
   ```

ntfy reads `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS` on every startup and syncs
them into the auth DB. The token (`tk_...`) is what you use as `NTFY_TOKEN` in
Forgejo secrets and all `curl` calls.

Create a secret using this token in order to reference in requests as bearer
token:

```sh
kubectl create secret generic ntfy-node-token -n ntfy \
  --from-literal=token=$(kubectl get secret -n ntfy \
  ntfy-auth -o jsonpath='{.data.auth-tokens}' | base64 -d | awk -F: '{print $2}')
```

## Install

```bash
kubectl create namespace ntfy
kubectl apply -f k3s-ha-cluster/ntfy/secret.yaml

helm upgrade --install ntfy k3s-ha-cluster/ntfy \
  --namespace ntfy \
  -f k3s-ha-cluster/ntfy/values.yaml
```

On first start, ntfy reads `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS` from the
secret and provisions them into the auth DB automatically. No exec needed.

## Publishing a notification

```bash
curl -H "Authorization: Bearer tk_YOURTOKEN" \
     -H "Title: Test" \
     -d "Hello from homelab" \
     https://ntfy.yukselcloud.com/homelab-deploys
```

## Node disk alerts

A node-level alert can post to a generic topic like `homelab-node` using a DaemonSet.
This runs one pod per node and checks the host filesystem every hour.

Apply the manifest in the `ntfy` namespace and create a token secret before use:

```bash
kubectl apply -f ntfy/node-disk-alerts.yaml
```

If you want the alert topic to be more specific, change `NTFY_TOPIC` in the
manifest from `homelab-node` to any topic you prefer.

## Integrations

<!-- markdownlint-disable MD013 -->
| Source          | Topic             | How                                                           |
| --------------- | ----------------- | ------------------------------------------------------------- |
| Forgejo Actions | `homelab-deploys` | `NTFY_TOKEN` repo secret + `curl` in workflow                 |
| Alertmanager    | `homelab-alerts`  | `ntfy-alertmanager` bridge in `monitoring/` namespace         |
| Radarr / Sonarr | `homelab-media`   | Settings → Connect → Webhook, `Authorization: Bearer` header  |
| Jellyfin        | `homelab-media`   | Dashboard → Plugins → Webhook                                 |
<!-- markdownlint-enable MD013 -->

## Links

- [ntfy docs](https://docs.ntfy.sh/)
- [ntfy config reference](https://docs.ntfy.sh/config/)
- [ntfy integrations](https://docs.ntfy.sh/integrations/)
