# opencode-agent

RBAC for the always-on opencode server (ct 253, lab-pve2) that manages the
homelab remotely over Tailscale. Replaces handing it your personal
cluster-admin kubeconfig.

## Design

Two-tier, read-broad / write-narrow:

- **Read** — `ClusterRoleBinding` to the built-in `view` role, cluster-wide.
  Lets opencode `get`/`list`/`watch` almost everything for debugging, but
  never Secrets, Roles, or RoleBindings.
- **Write** — `RoleBinding` to the built-in `edit` role, one namespace at a
  time (`rolebinding-<namespace>-edit.yaml`). Only namespaces with a
  RoleBinding are writable. Nothing is writable cluster-wide.

## Apply

```bash
kubectl apply -f namespace.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f token-secret.yaml
kubectl apply -f clusterrolebinding-view.yaml
kubectl apply -f rolebinding-media-edit.yaml
kubectl apply -f rolebinding-monitoring-edit.yaml
```

Add write access to another namespace: copy `rolebinding-media-edit.yaml`,
change `metadata.namespace`, apply. (These could also live inside each
service's own folder, e.g. `media/rolebinding-opencode-agent.yaml`, if you'd
rather keep the grant next to the thing it grants access to — either layout
works with `kubectl apply -f <namespace>/`.)

## Generate the kubeconfig

```bash
../../generate-kubeconfig.sh > opencode-agent.kubeconfig
scp opencode-agent.kubeconfig root@192.168.0.53:/root/.kube/config
```

Then in `bootstrap-opencode-lxc.sh` (same `lxc/opencode/` folder), set
`KUBECONFIG_SRC` to `opencode-agent.kubeconfig` instead of `$HOME/.kube/config`
(the script already defaults to the scoped kubeconfig at
`temp/opencode-agent.kubeconfig`).

## Revoking access

Delete the token Secret (`kubectl -n opencode-agent delete secret
opencode-agent-token`) — the kubeconfig on ct53 stops working immediately,
no need to touch the LXC itself.
