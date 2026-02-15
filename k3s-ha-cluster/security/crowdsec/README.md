# CrowdSec

Detects malicious behavior from Caddy access logs and blocks offending IPs via
the bouncer module built into Caddy. Backed by MySQL in the `db` namespace.

## Architecture

```text
Internet → Caddy (crowdsec bouncer) → checks LAPI decisions → 403 or proxy
                                              ↑
            CrowdSec Agent → parses Caddy logs → CrowdSec LAPI (MySQL)
```

- **Agent** (DaemonSet) — reads Caddy pod logs, detects attack patterns
- **LAPI** (Deployment) — stores decisions in MySQL, serves bouncer API,
syncs with CrowdSec Central API
- **Caddy** — Image is selected from [`ghcr.io/serfriz/caddy-cloudflare-crowdsec`](https://github.com/serfriz/caddy-custom-builds)

## Prerequisites

- MySQL deployed in `db` namespace (see [mysql/README.md](../../mysql/README.md))
- The `crowdsec` database and user must exist in MySQL
- A copy of the MySQL password secret in the `crowdsec` namespace
([mysql-secret.yaml](mysql-secret.yaml)) — must match the one in `mysql/secret.yaml`

## Install

```bash
kubectl create namespace crowdsec
kubectl apply -f security/crowdsec/mysql-secret.yaml

# Generate a bouncer key and set it in both:
#   - values.yaml (BOUNCER_KEY_caddy)
#   - caddy/crowdsec-bouncer-secret.yaml (CROWDSEC_API_KEY)
openssl rand -base64 32

helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm repo update
helm upgrade --install crowdsec crowdsec/crowdsec \
  --namespace crowdsec \
  -f security/crowdsec/values.yaml
```

`values.yaml` config:

- `BOUNCER_KEY_caddy` — bouncer API key (must match `caddy/crowdsec-bouncer-secret.yaml`)
- `ENROLL_KEY` — optional, for [CrowdSec Console](https://app.crowdsec.net/) enrollment
- `DB_*` env vars — MySQL connection (points to `mysql.db.svc.cluster.local`)

## Caddy Integration

Caddy's service must use `externalTrafficPolicy: Local` to preserve real client
IPs — otherwise kube-proxy SNATs everything to an internal pod IP and the
bouncer can't match decisions.

```bash
kubectl apply -f caddy/crowdsec-bouncer-secret.yaml
kubectl apply -f caddy/configmap.yaml
kubectl apply -f caddy/service.yaml
kubectl rollout restart deployment/caddy -n caddy
```

## Useful Commands

```bash
LAPI_POD=$(kubectl get pods -n crowdsec \
  -l k8s-app=crowdsec -l type=lapi -o name)
LAPI="kubectl exec -n crowdsec -it $LAPI_POD --"

$LAPI cscli bouncers list      # bouncer status
$LAPI cscli alerts list        # detected attacks
$LAPI cscli decisions list     # active bans
$LAPI cscli metrics            # parsing & decision stats
$LAPI cscli capi status        # central API connectivity
```

## Links

- [CrowdSec Docs](https://docs.crowdsec.net/)
- [CrowdSec Hub](https://hub.crowdsec.net/) — collections & scenarios
- [CrowdSec Console](https://app.crowdsec.net/) — central dashboard
- [Caddy CrowdSec Bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer)
- [Caddy Custom Builds](https://github.com/serfriz/caddy-custom-builds)
