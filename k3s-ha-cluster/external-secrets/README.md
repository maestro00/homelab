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
values. `deploy-external-secrets.yml` seeds these keys from Forgejo repo
secrets (the same push-driven pattern as DDNS):

| Key                             | Source                          |
| ------------------------------- | ------------------------------- |
| `forgejo-read-token`            | `FORGEJO_READ_TOKEN`            |
| `vaultwarden-admin-token`       | `VAULTWARDEN_ADMIN_TOKEN`       |
| `vaultwarden-sso-client-id`     | literal `vaultwarden`           |
| `vaultwarden-sso-client-secret` | `VAULTWARDEN_SSO_CLIENT_SECRET` |

The `speedtest-*` keys are seeded separately and must survive the merge patch.

## Auth stack

`auth-secrets.yaml` declares five ExternalSecrets in namespace `auth` and is
applied by `deploy-external-secrets.yml` because Authelia and lldap are
Helm-source Applications.

- `authelia-secrets` ← `authelia-reset-password-jwt-hmac-key`,
  `authelia-session-encryption-key`, `authelia-storage-encryption-key`,
  `redis-password`, `authelia-ldap-password`, `authelia-oidc-hmac-key`
- `oidc-clients` ← `authelia-oidc-forgejo-client-secret-hash`,
  `authelia-oidc-jellyfin-client-secret-hash`,
  `authelia-oidc-vaultwarden-client-secret-hash`
- `jwk-rsa` ← `authelia-jwk-rsa-private-key`
- `lldap-credentials` ← `lldap-jwt-secret`, `lldap-admin-username`,
  `lldap-admin-password`, `lldap-base-dn`
- `redis-secret` ← `redis-password`

The Forgejo repository secret names are the upper-snake-case form shown in
the workflow: `AUTHELIA_*`, `LLDAP_*`, and `REDIS_PASSWORD`.

## RBAC

The Kubernetes provider cannot use the operator's own ServiceAccount (by
design, to avoid cross-namespace reads), so `store-rbac.yaml` creates a
dedicated `gitops-store` ServiceAccount with read-only Secret access plus
`selfsubjectrulesreviews`.

## Adding a secret (worked flow)

Three pieces: the value (cluster only), the `ExternalSecret` declaration
(Git), and no placeholder `secret.yaml`.

1. Recover the current value from the live Secret (it lives in the cluster,
   never Git):

   ```bash
   kubectl -n <app> get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
   ```

2. Seed it into the source store:

   ```bash
   kubectl -n external-secrets patch secret gitops-secrets --type merge \
     --patch '{"stringData":{"<app>-<key>":"<value>"}}'
   ```

3. Declare the `ExternalSecret` (references the value by key name only):

   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: <name>
     namespace: <app>
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: gitops
       kind: ClusterSecretStore
     target:
       name: <name>
     data:
       - secretKey: <KEY>
         remoteRef:
           key: gitops-secrets
           property: <app>-<key>
   ```

4. Delete the old placeholder `secret.yaml` from the app folder so nothing
   overwrites the real value again.

5. Apply it. Where the file lives depends on how the app is deployed:

   - Raw-manifest app (Argo CD `directory` source): co-locate
     `externalsecret.yaml` in the app folder — Argo CD applies it. See
     `speedtest-tracker/externalsecret.yaml`.
   - Helm app (Argo CD `helm` source): the chart ignores extra YAML in the
     folder, so keep the `ExternalSecret` in this folder and list it in
     `deploy-external-secrets.yml`. See `homepage-secrets.yaml`.

## Existing consumers

- `argocd-repo-credential.yaml` — the `repository`-labelled Secret Argo CD uses
  to clone this repo.
- `homepage-secrets.yaml` — homepage widget API keys (`HOMEPAGE_VAR_*`).
- `speedtest-tracker/externalsecret.yaml` — `speedtest-db-secret` (`app-key`,
  `password`), co-located because speedtest is a raw-manifest app.
