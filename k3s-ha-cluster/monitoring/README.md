# Monitoring (Beszel)

This directory holds raw manifests for [Beszel](https://beszel.com), the
lightweight host/container monitoring stack. It replaces the former
Grafana/Prometheus (kube-prometheus-stack) deployment.

## Components

| File | What it creates |
|------|-----------------|
| `deployment.yaml` | Beszel hub (web UI + database), served at `https://beszel.yukselcloud.com` |
| `service.yaml` | LoadBalancer `192.168.0.225` → hub port 8090 |
| `pvc.yaml` | Longhorn PVC `beszel-data` (2Gi, hub database) |
| `secret.yaml` | `beszel-agent` secret (KEY/TOKEN for agent registration) |
| `agent-daemonset.yaml` | `beszel-agent` DaemonSet — one agent pod per node (host network, port 45876) |

## Deploying

```bash
kubectl apply -f monitoring/beszel/
```

Caddy serves the hub via the `beszel.yukselcloud.com` block in
`caddy/configmap.yaml`; the `beszel.monitoring.svc.cluster.local:8090` backend
is referenced there.

## Adding a node

The DaemonSet already runs an agent on every node. Add a host in the Beszel
UI using its node IP and port 45876 with the KEY from the `beszel-agent`
secret.

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

- Agents use `hostNetwork: true` so the hub reaches them at `<node-ip>:45876`.
- The hub itself is pinned to the MetalLB IP `192.168.0.225`; keep this in
  sync with the agent's `HUB_URL` and the Caddy backend.
- Alerting is handled by Uptime Kuma (see `monitoring/uptime-kuma/`) — Beszel
  covers system metrics, Uptime Kuma covers endpoint health checks.
