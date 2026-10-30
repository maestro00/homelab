# Telegram agent

Use the sibling repository as canonical:

- [README](../../../../../telegram-agent/README.md) for commands and setup.
- [Deployment](../../../../../telegram-agent/manifests/deployment.yaml) for
  runtime configuration.
- [RBAC](../../../../../telegram-agent/manifests/clusterrole-actions.yaml)
  for permitted mutations.
- [Workflows](../../../../../telegram-agent/.forgejo/workflows/) for the
  `deploy-telegram-agent.yaml` build and deployment pipeline.

## Architecture

The Go bot performs Kubernetes status checks, confirmed workload restarts,
CronJob reruns, and Forgejo workflow dispatches. It runs one replica in the
`telegram-agent` namespace and uses outbound Telegram long polling.

It has no Service, Ingress, MetalLB address, or Caddy route. Do not add
external exposure to fix Telegram connectivity; inspect outbound network,
credentials, pod logs, and RBAC instead.

## Change checklist

- Require confirmation and an allowlisted chat for mutating commands.
- When adding a managed namespace, update both the application allowlist
  and the matching RoleBinding; verify their current locations in the repo.
- Create runtime credentials separately and never load the real secret
  manifest for routine context.
- Keep cluster-wide read access separate from narrowly scoped write access.
