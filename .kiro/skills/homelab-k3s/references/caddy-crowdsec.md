# Caddy + CrowdSec + Authelia Reference

Based on actual `caddy/configmap.yaml` from the repo.

---

## Caddy Image

```bash
ghcr.io/serfriz/caddy-cloudflare-crowdsec
```

This is a custom Caddy build with the CrowdSec bouncer and Cloudflare DNS modules
baked in. Do NOT use the plain `caddy:latest` image — it won't have the bouncer.

---

## Real Caddyfile Structure (from repo)

```caddyfile
{
  order crowdsec first

  crowdsec {
    api_url http://crowdsec-service.crowdsec.svc.cluster.local:8080
    api_key {env.CROWDSEC_API_KEY}    # from crowdsec-bouncer-secret.yaml
    ticker_interval 15s
  }
}

# --- Auth ---
auth.yukselcloud.com {
  log
  crowdsec
  reverse_proxy authelia.auth.svc.cluster.local:9091 {
    header_up Host {host}
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Uri {uri}
    header_up X-Forwarded-For {remote_host}
    transport http {
      read_timeout 30s
      write_timeout 30s
      dial_timeout 10s
    }
  }
}

# --- Standard service (Grafana, Stirling PDF, Forgejo) ---
grafana.yukselcloud.com {
  log
  crowdsec
  reverse_proxy prometheus-grafana.monitoring.svc.cluster.local:80 {
    header_up Host {host}
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Uri {uri}
    header_up X-Forwarded-For {remote_host}
    transport http {
      read_timeout 30s
      write_timeout 30s
      dial_timeout 10s
    }
  }
}

# --- Jellyfin (different header set) ---
jellyfin.yukselcloud.com {
  log
  crowdsec
  reverse_proxy jellyfin.media.svc.cluster.local:8096 {
    header_up X-Forwarded-Proto {scheme}   # note: {scheme} not https
    header_up X-Forwarded-Host {host}
    header_up X-Real-IP {remote_host}
    # no transport block — Jellyfin doesn't need it
  }
}

# --- Simple service ---
demo.yukselcloud.com {
  log
  crowdsec
  reverse_proxy demo-service.caddy-web-demo.svc.cluster.local:80
}
```

---

## Adding a New Route — Step by Step

### 1. Find the service DNS name and port

```bash
kubectl get svc -n <namespace>
# format: <svc-name>.<namespace>.svc.cluster.local:<port>
```

### 2. Decide on template

**Standard service** (most cases — use the full header set with transport block):

```caddyfile
myservice.yukselcloud.com {
  log
  crowdsec
  reverse_proxy myservice.mynamespace.svc.cluster.local:8080 {
    header_up Host {host}
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Uri {uri}
    header_up X-Forwarded-For {remote_host}
    transport http {
      read_timeout 30s
      write_timeout 30s
      dial_timeout 10s
    }
  }
}
```

**Simple service** (no auth layer, no special headers needed):

```caddyfile
myservice.yukselcloud.com {
  log
  crowdsec
  reverse_proxy myservice.mynamespace.svc.cluster.local:8080
}
```

### 3. Edit `caddy/configmap.yaml`

Add the new block to the `Caddyfile: |` data section.

### 4. Apply + restart

```bash
kubectl apply -f k3s-ha-cluster/caddy/configmap.yaml
kubectl rollout restart deployment/caddy -n caddy
kubectl rollout status deployment/caddy -n caddy
```

### 5. If externally accessible — update DDNS

Add to `ddns/config.json`:

```json
{ "name": "myservice", "proxied": false }
```

Then regenerate and apply the secret:

```bash
kubectl create secret generic config-cloudflare-ddns \
  --from-file=config.json \
  --dry-run=client -oyaml -n ddns > config-cloudflare-ddns-Secret.yaml
kubectl apply -f config-cloudflare-ddns-Secret.yaml
kubectl rollout restart deployment/cloudflare-ddns -n ddns
```

---

## Authelia Forward-Auth Pattern

For services that don't support OIDC natively (Homer, Longhorn UI, K8s dashboard):

```caddyfile
myservice.yukselcloud.com {
  log
  crowdsec
  forward_auth authelia.auth.svc.cluster.local:9091 {
    uri /api/authz/forward-auth
    copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
  }
  reverse_proxy myservice.mynamespace.svc.cluster.local:8080 {
    header_up Host {host}
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Uri {uri}
    header_up X-Forwarded-For {remote_host}
  }
}
```

Note: `forward_auth` comes BEFORE `reverse_proxy` — Caddy evaluates top-down.

---

## Authelia OIDC (Forgejo, Jellyfin)

Add new OIDC client to `auth/authelia/values.yaml` under `identity_providers.oidc.clients`:

```yaml
- client_id: my-service
  client_name: My Service
  client_secret: '$argon2id$...'
  # generate: docker run authelia/authelia:latest authelia crypto hash generate
  # pbkdf2 --password 'mysecret'
  public: false
  authorization_policy: one_factor
  redirect_uris:
    - https://myservice.yukselcloud.com/oauth/callback
  scopes:
    - openid
    - profile
    - email
    - groups
  grant_types:
    - authorization_code
```

After editing values.yaml:

```bash
helm upgrade authelia authelia/authelia -n auth --values auth/authelia/values.yaml
```

---

## CrowdSec Bouncer Key Setup

The bouncer key links Caddy to the CrowdSec LAPI. It must be set in two places:

**1. CrowdSec Helm values** (`security/crowdsec/values.yaml`):

```yaml
config:
  BOUNCER_KEY_caddy: "your-generated-key"  # openssl rand -base64 32
```

**2. Caddy secret** (`caddy/crowdsec-bouncer-secret.yaml`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: crowdsec-bouncer-secret
  namespace: caddy
type: Opaque
stringData:
  CROWDSEC_API_KEY: "your-generated-key"   # same key as above
```

The Caddy deployment mounts this secret as an env var, which Caddy reads as `{env.CROWDSEC_API_KEY}`.

---

## CrowdSec Useful Commands

```bash
LAPI_POD=$(
  kubectl get pods -n crowdsec -l k8s-app=crowdsec,type=lapi -o name | head -1
)

kubectl exec -n crowdsec -it $LAPI_POD -- cscli bouncers list    # check bouncer
kubectl exec -n crowdsec -it $LAPI_POD -- cscli alerts list      # detected attacks
kubectl exec -n crowdsec -it $LAPI_POD -- cscli decisions list   # active IP bans
kubectl exec -n crowdsec -it $LAPI_POD -- cscli metrics          # parsing stats
kubectl exec -n crowdsec -it $LAPI_POD -- cscli capi status      # central API status
```

---

## Troubleshooting Auth

```bash
# Authelia logs
kubectl logs -n auth -l app.kubernetes.io/name=authelia --tail=100

# lldap
kubectl logs -n auth deployment/lldap --tail=50

# Redis
kubectl logs -n auth deployment/redis --tail=30

# Restart after values.yaml change
helm upgrade authelia authelia/authelia -n auth --values auth/authelia/values.yaml

# Common issues:
# Login loop          → CORS or session cookie domain mismatch in Authelia config
# Timeout on /        → access_control rules catching the root path
# OIDC redirect error → redirect_uri doesn't match exactly (trailing slash matters)
# CrowdSec 403        → real IP not preserved; check externalTrafficPolicy: Local
#                       on Caddy svc
```
