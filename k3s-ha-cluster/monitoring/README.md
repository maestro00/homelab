# Monitoring (Beszel + Loki + Grafana + Uptime Kuma)

This directory holds the observability stack:

| Tool | What it covers | Deployed via |
| ------ | ----------------- | -------------- |
| [Beszel](https://beszel.com) | Host/container metrics | raw manifests |
| [Loki](https://grafana.com/oss/loki/) | Centralized pod logs | Helm |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log shipper (DaemonSet) | Helm |
| [Grafana](https://grafana.com) | Loki query UI | Helm |
| [Uptime Kuma](https://uptime.kuma.pet) | Synthetic checks + TLS expiry | raw manifests |

---

## Beszel

Lightweight host/container metrics, replacing the former Grafana/Prometheus
(kube-prometheus-stack) deployment.

### Components

| File | What it creates |
| ------ | ----------------- |
| `deployment.yaml` | Beszel hub `https://beszel.yukselcloud.com` |
| `service.yaml` | LoadBalancer `192.168.0.225` → hub port 8090 |
| `pvc.yaml` | Longhorn PVC `beszel-data` (2Gi, hub database) |
| `secret.yaml` | `beszel-agent` secret (KEY/TOKEN for agent registration) |
| `agent-daemonset.yaml` | Beszel agent per node; host network, port 45876 |

### Deploying

```bash
kubectl apply -f monitoring/beszel/
```

Caddy serves the hub via the `beszel.yukselcloud.com` block in
`caddy/configmap.yaml`; the `beszel.monitoring.svc.cluster.local:8090` backend
is referenced there.

### Adding a node

The DaemonSet already runs an agent on every node. Add a host in the Beszel
UI using its node IP and port 45876 with the KEY from the `beszel-agent`
secret.

---

## Loki + Promtail + Grafana (logs)

Centralized, searchable pod logs. Promtail (a DaemonSet) tails `/var/log/pods`
on every node and ships to Loki (single-binary, filesystem on Longhorn);
Grafana is the query UI at `https://grafana.yukselcloud.com`.

Auth is handled at the Caddy edge — both `grafana` and `dashboard` use Authelia
`forward_auth` (gated to `group:infra`), and Grafana trusts the `Remote-User`
header, so there is no separate Grafana login form.

### Deploying

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki \
  --version 7.5.0 --namespace monitoring -f monitoring/loki/values.yaml

helm upgrade --install promtail grafana/promtail \
  --version 6.17.1 --namespace monitoring -f monitoring/promtail/values.yaml

helm upgrade --install grafana grafana/grafana \
  --version 10.5.15 --namespace monitoring -f monitoring/grafana/values.yaml
```

Grafana ships with a provisioned `Loki` datasource (default) pointing at
`http://loki.monitoring.svc.cluster.local:3100`, so `Explore → Loki` works out
of the box.

### Notes

- Loki is single-binary (`deploymentMode: SingleBinary`); the scale-out
  memcached caches are disabled (`chunksCache`/`resultsCache`), as they can't
  schedule and aren't needed at this scale.
- `shortcut:` Promtail is deprecated upstream in favour of Grafana Alloy.
  Migrate to `grafana/alloy` when Promtail stops receiving security patches.
- Loki filesystem storage on a 10Gi Longhorn PVC; prune/expand as needed.

---

## Uptime Kuma (synthetic checks + TLS cert expiry)

Raw manifests in `uptime-kuma/` — Deployment + ClusterIP service + Longhorn PVC
(`uptime-kuma-data`), proxied by Caddy at `https://uptime-kuma.yukselcloud.com`.

```bash
kubectl apply -f monitoring/uptime-kuma/
```

On first login, create the admin account at `https://uptime-kuma.yukselcloud.com`,
then add HTTP(S) monitors for the public services plus TLS certificate monitors,
with notifications sent to the ntfy provider
(`https://ntfy.yukselcloud.com/homelab-alerts`).

## Notes

- Beszel agents use `hostNetwork: true` so the hub reaches them at
  `<node-ip>:45876`.
- The Beszel hub is pinned to the MetalLB IP `192.168.0.225`; keep this in
  sync with the agent's `HUB_URL` and the Caddy backend.
- Alerting is handled by Uptime Kuma — Beszel covers system metrics, Loki/Grafana
  cover logs, Uptime Kuma covers endpoint health checks.
