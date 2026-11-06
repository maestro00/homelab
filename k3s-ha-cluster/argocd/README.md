# Argo CD

Pull-based GitOps controller for the cluster. Installs via Forgejo Action, then
reconciles the app-of-apps tree under `apps/`.

- Chart: `argo/argo-cd` `10.11.6`, app `v3.5.6` (pinned in `values.yaml`)
- Exposed at `argocd.yukselcloud.com` behind Caddy (plain HTTP; Caddy
  terminates TLS)
- Admin login uses the generated `admin` password (below); Authelia SSO is a
  follow-up

## Bootstrap order

Argo CD depends on External Secrets Operator for its repo credential. Onboard
in this order:

1. Create a read-only Forgejo access token for `lab/homelab`.
2. Add it as the Forgejo repo secret `FORGEJO_READ_TOKEN`.
3. Push `external-secrets/` and `argocd/` (both workflows run).

`deploy-external-secrets.yml` seeds the cluster store and materializes the
`argocd-repo` Secret; `deploy-argocd.yml` installs Argo CD and applies the
root `app-of-apps`.

## First login

Retrieve the generated admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` at `https://argocd.yukselcloud.com`. Rotate the password, and
move to Authelia SSO as a follow-up.

## App-of-apps

The root `Application` (`app-of-apps.yaml`) points at `apps/`, a Kustomize
directory. To migrate a service, drop a child `Application` YAML into `apps/`
and list it in `apps/kustomization.yaml`.

## Managed applications

- `authelia` — chart `authelia/authelia` `0.10.49`, adopted from the manual
  Helm release.
- `lldap` — in-repo chart, adopted from the manual Helm release.
- `redis` — raw manifests, adopted from the manual manifests.
- `speedtest-tracker` — raw manifests.
- `vaultwarden` — chart `vaultwarden/vaultwarden`.

## Access

Served by Caddy without Authelia `forward_auth` (Argo CD has its own RBAC),
like Forgejo. CrowdSec still filters at the edge.
