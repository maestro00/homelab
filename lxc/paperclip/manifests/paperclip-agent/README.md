# paperclip-agent

RBAC for the two agents running on ct 254 (lab-pve1). Each agent gets its own
ServiceAccount and its own kubeconfig, so a mistake by one cannot use the other
one's permissions.

## Design

Two agents, two scopes:

| Agent  | Grant                             | Namespaces                 |
| ------ | --------------------------------- | -------------------------- |
| ops    | ClusterRole `view`, cluster-wide  | all (read-only)            |
| deploy | ClusterRole `edit`, per namespace | media, monitoring, opengym |

`view` is cluster-wide read for workloads, events and logs, and excludes
Secrets, Roles and RoleBindings. `edit` can change workloads but not RBAC.
Nothing is writable cluster-wide.

> Read `view` literally: it also excludes `nodes`, custom resources such as
> `longhorn.io`, and `storage.k8s.io`. An agent using it can report pod and
> event data but cannot see node pressure or volume health, and should say so
> instead of implying the cluster is clean.

> `edit` does grant read on Secrets inside its namespaces. Treat every
> namespace listed for `deploy` as readable by that agent.

> Both kubeconfig files live in one user's home (`/srv/paperclip/.kube`) on
> ct254. The split limits what each *credential* can do; it is not an OS
> boundary, and it is not a defence against a board admin reconfiguring an
> agent. The real guardrail is that agents propose and a human merges.

Adding write access for another namespace: copy one document out of
`rolebinding-deploy-edit.yaml`, change `metadata.namespace`, apply.

## Apply

```bash
kubectl apply -f namespace.yaml
kubectl apply -f serviceaccount-ops.yaml -f serviceaccount-deploy.yaml
kubectl apply -f token-secrets.yaml
kubectl apply -f clusterrolebinding-ops-view.yaml
kubectl apply -f rolebinding-deploy-edit.yaml
```

## Generate the kubeconfigs

The bootstrap script expects them at `temp/paperclip-{ops,deploy}.kubeconfig`:

```bash
./generate-kubeconfig.sh ops    > ../../temp/paperclip-ops.kubeconfig
./generate-kubeconfig.sh deploy > ../../temp/paperclip-deploy.kubeconfig
```

Prove the scoping before handing them over:

```bash
KUBECONFIG=../../temp/paperclip-ops.kubeconfig \
  kubectl auth can-i --list
KUBECONFIG=../../temp/paperclip-deploy.kubeconfig \
  kubectl -n auth auth can-i create deployments   # expect: no
```

## Revoking access

Delete the token Secret (`kubectl -n paperclip-agent delete secret ops-token`).
The matching kubeconfig stops working immediately; no need to touch the
container.
