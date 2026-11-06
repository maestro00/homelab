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

The Forgejo repository secrets seed `gitops-secrets`. After changing one, run
the `Deploy External Secrets` workflow, force the matching ExternalSecret,
and restart its consumer.

- `AUTHELIA_OIDC_<CLIENT>_CLIENT_SECRET_HASH` → `oidc-clients`; restart
  `daemonset/authelia`. The hash is a file, so the pod must restart.
- `AUTHELIA_OIDC_HMAC_KEY` → `authelia-secrets`; restart Authelia. Existing
  OIDC tokens are invalidated.
- `AUTHELIA_JWK_RSA_PRIVATE_KEY` → `jwk-rsa`; restart Authelia. Tokens signed
  with the old key may fail until they refresh.
- `LLDAP_JWT_SECRET` → `lldap-credentials`; restart `deployment/lldap`.
  Existing lldap UI sessions are invalidated.
- `REDIS_PASSWORD` → `redis-secret` and `authelia-secrets`; restart Redis,
  then Authelia. One source key feeds both targets.
- `AUTHELIA_LDAP_PASSWORD` → `authelia-secrets`; restart Authelia.
- `LLDAP_ADMIN_PASSWORD` → `lldap-credentials`; restart lldap.

Two credentials need extra care:

- `AUTHELIA_LDAP_PASSWORD` and `LLDAP_ADMIN_PASSWORD` are the same
  credential. Change both Forgejo secrets together. lldap applies its admin
  password only when it first creates the admin user; use
  `extraEnv: LLDAP_FORCE_LDAP_USER_PASS_RESET=true` for one rollout and then
  remove it, or reset the admin password in the lldap UI.
- `AUTHELIA_STORAGE_ENCRYPTION_KEY` and `AUTHELIA_SESSION_ENCRYPTION_KEY` are
  not routine rotations. The first makes existing Authelia data unreadable;
  the second signs out every user. Plan a migration.

Force the affected ExternalSecret and restart its consumer:

```bash
kubectl -n auth annotate externalsecret oidc-clients \
  force-sync="$(date +%s)" --overwrite
kubectl -n auth rollout restart daemonset/authelia
```

## Rollback

`git revert` the values or manifest change and let Argo CD sync. Argo CD does
not revert External Secrets; re-seed the affected values from Forgejo and
force the refresh. Keep `/tmp/opencode/authelia-gitops-backup/` until the
stack has run for a week; it is not durable storage.

## Auth flow

```text
Browser
 └─ Caddy
     ├─ forward_auth → Authelia → LDAP → lldap
     │                         └─ sessions → Redis
     └─ application
```
