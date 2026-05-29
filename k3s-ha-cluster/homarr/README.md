# homarr

Modern drag-and-drop homelab dashboard with service integrations.

- Deployed via the official Homarr Helm chart in the `homarr` namespace
- exposed via Caddy at `homarr.yukselcloud.com`
- Auth via Authelia OIDC

## Prerequisites

### 1. Register the OIDC client in Authelia

Generate a hashed secret:

```bash
authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72
```

Add the client to `k3s-ha-cluster/auth/authelia/values.yaml` under
`configMap.identity_providers.oidc.clients`:

```yaml
- client_id: homarr
  client_name: Homarr
  client_secret: "$pbkdf2-sha512$310000$..."   # hash from above
  public: false
  authorization_policy: one_factor
  require_pkce: true
  redirect_uris:
    - https://homarr.yukselcloud.com/api/auth/callback/oidc
  scopes: [openid, email, profile, groups]
  grant_types: [authorization_code]
  response_types: [code]
  claims_policy: legacy
```

Apply Authelia:

```bash
helm upgrade authelia authelia/authelia -n auth -f k3s-ha-cluster/auth/authelia/values.yaml
```

### 2. Fill in `secret.yaml`

```yaml
# auth-oidc-secret
oidc-client-id: "homarr"
oidc-client-secret: "<plaintext from authelia crypto hash generate>"

# db-encryption
db-encryption-key: "<openssl rand -hex 32>"
```

## Install

```bash
helm repo add homarr-labs https://homarr-labs.github.io/charts/
helm repo update

kubectl create namespace homarr
kubectl apply -f k3s-ha-cluster/homarr/secret.yaml

helm upgrade --install homarr homarr-labs/homarr \
  --namespace homarr \
  -f k3s-ha-cluster/homarr/values.yaml
```

## Onboarding (first time only)

On first deploy, go to `https://homarr.yukselcloud.com/init` to run the onboarding
wizard. When asked for the external admin group name, enter the lldap group your
admin user belongs to (e.g. `infra`). Then assign admin permissions to that group
in Manage → Users → Groups.

Make sure the user is actually a member of that group in lldap — group sync happens
on every OIDC login.

## Caddy

Entry already added to `k3s-ha-cluster/caddy/configmap.yaml`. Roll Caddy to pick
it up:

```bash
kubectl rollout restart deployment caddy -n caddy
```

## Links

- [Homarr Helm chart](https://homarr-labs.github.io/charts/charts/homarr/)
- [Environment variables](https://homarr.dev/docs/advanced/environment-variables/)
- [SSO / OIDC](https://homarr.dev/docs/advanced/single-sign-on/)
