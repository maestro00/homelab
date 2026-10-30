---
name: homelab-k3s
description: >
  Use when working on Tay's yukselcloud.com K3s workloads: Helm, Kubernetes
  manifests, kubectl debugging, Caddy or MetalLB ingress, Longhorn,
  namespaces, Forgejo Actions, Homepage, Beszel, or Uptime Kuma. Do not use
  for Proxmox VM or LXC provisioning; use homelab-terraform instead.
---

# Homelab K3s

Use the homelab repository and live cluster as canonical sources. Explain
new concepts before showing configuration.

## Durable rules

- The HA cluster has three control planes and two workers. Keep Longhorn off
  the Pi and Caddy on the designated ingress nodes.
- Use Caddy, not Traefik or nginx. Preserve `externalTrafficPolicy: Local`
  where client-IP-based CrowdSec enforcement depends on it.
- Prefer a maintained upstream Helm chart. Use custom charts or raw
  manifests only when they fit the existing repository pattern better.
- Keep secrets out of Git; follow the existing placeholder and Forgejo
  secret patterns.

## Load only what the task needs

- Current topology: [shared topology](../shared/topology.md).
- New services, Helm values, or manifests:
  [deployment patterns](references/patterns.md).
- Caddy, Authelia, CrowdSec, or exposure:
  [Caddy reference](references/caddy-crowdsec.md) and
  [route onboarding](references/add-service-to-caddy.md).
- Kubernetes debugging or operations:
  [kubectl workflows](references/kubectl-workflows.md).
- Forgejo workflows, API, issues, registry, or roadmap:
  [Forgejo reference](references/forgejo-api-and-ci.md).
- Router, DNS, or Tailscale:
  [network reference](references/router-and-tailscale.md).
- Telegram bot deployment or connectivity:
  [Telegram agent](references/telegram-agent.md).

Paperclip, Argo CD, Homepage, monitoring, recovery, and hardening issues are
plans until verified in the repository or cluster. Query current issues
instead of treating roadmap entries as deployed architecture.
