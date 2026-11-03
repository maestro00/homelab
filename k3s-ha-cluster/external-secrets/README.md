# External Secrets Operator

Kubernetes-native secret store: Git declares `ExternalSecret` resources, the
values live in a cluster-side source Secret, and ESO reconciles the two.

- Chart: `external-secrets/external-secrets` `2.14.0`, app `v2.14.0`
- Store: `ClusterSecretStore` named `gitops`, backed by the Kubernetes provider
  reading the `external-secrets` namespace

## Why

Argo CD pulls from Git and cannot read Forgejo repo secrets. ESO keeps secret
values out of Git while Argo CD reconciles everything else.

## Source of truth

A single `gitops-secrets` Secret in the `external-secrets` namespace holds all
values. `deploy-external-secrets.yml` seeds it from the Forgejo repo secret
`FORGEJO_READ_TOKEN` (the same push-driven pattern as DDNS). Extend the seed
step to add more keys.

## RBAC

The Kubernetes provider cannot use the operator's own ServiceAccount (by
design, to avoid cross-namespace reads), so `store-rbac.yaml` creates a
dedicated `gitops-store` ServiceAccount with read-only Secret access plus
`selfsubjectrulesreviews`.

## Adding a secret

Add the value to the `gitops-secrets` source Secret, then declare:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-secret
  namespace: my-app
spec:
  secretStoreRef:
    name: gitops
    kind: ClusterSecretStore
  target:
    name: my-secret
  data:
    - secretKey: token
      remoteRef:
        key: gitops-secrets
        property: my-token
```

The first real consumer is the Argo CD repo credential
(`argocd-repo-credential.yaml`), which produces the `repository`-labelled
Secret Argo CD uses to clone this repo.
