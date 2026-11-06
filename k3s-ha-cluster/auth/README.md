# Authentication Stack

Authelia, lldap, and Redis run in the `auth` namespace and are managed by
Argo CD. This folder is the source for their values and manifests.

## Components

### Authelia

- Authentication gateway and OIDC provider.
- Integrates with Caddy through `forward_auth`.
- Uses lldap as the LDAP backend and Redis for sessions.
- Image: `ghcr.io/authelia/authelia:4.39.15`

### lldap

- Lightweight LDAP directory.
- Stores users and groups only.
- Internal access through the `lldap` and `lldap-service` Services.
- Image: `nitnelave/lldap:v0.6.1`

### Redis

- Session storage for Authelia.
- Password-protected; the password comes from the `redis-secret` Secret.
- Image: `redis:latest`

## Deployment

| Application | Source                                      |
| ----------- | ------------------------------------------- |
| `authelia`  | chart `authelia/authelia` `0.10.49`         |
| `lldap`     | in-repo chart `k3s-ha-cluster/auth/lldap`    |
| `redis`     | raw manifests in `k3s-ha-cluster/auth/redis` |

The Applications live in `k3s-ha-cluster/argocd/apps/` and are reconciled by
the app-of-apps. Do not run `helm upgrade` or `helm uninstall` for these
releases; Argo CD owns them. Change the values or manifests in Git.

## Secrets

External Secrets materializes five Secrets in `auth` from the
`gitops-secrets` source Secret:

| Target Secret       | Contents                                  |
| ------------------- | ----------------------------------------- |
| `authelia-secrets`  | six Authelia config secret files          |
| `oidc-clients`      | `forgejo`, `jellyfin`, `vaultwarden`      |
| `jwk-rsa`           | `private.pem`                             |
| `lldap-credentials` | four lldap credentials                    |
| `redis-secret`      | `redis-password`                          |

The OIDC client hashes are files in `oidc-clients`. The chart mounts them at
`/secrets/oidc-clients/<client>`, and `values.yaml` references them with
`client_secret.path`. No hash is stored in Git.

The declarations are in
`k3s-ha-cluster/external-secrets/auth-secrets.yaml`.

> Never change `storage.encryption.key` or `session.encryption.key` without a
> migration plan. The storage key encrypts existing Authelia data; the session
> key signs every active session.

## Rotation

1. Update the matching Forgejo repository secret (`AUTHELIA_*`, `LLDAP_*`, or
   `REDIS_PASSWORD`).
2. Run the `Deploy External Secrets` workflow.
3. Force the ExternalSecret refresh:

   ```bash
   kubectl -n auth annotate externalsecret authelia-secrets \
     force-sync="$(date +%s)" --overwrite
   ```

4. Restart the consumer:

   ```bash
   kubectl -n auth rollout restart daemonset/authelia
   ```

   Use `deployment/lldap` or `deployment/redis` for their secrets.

## Auth flow

```text
Browser
 └─ Caddy
     ├─ forward_auth → Authelia → LDAP → lldap
     │                         └─ sessions → Redis
     └─ application
```
