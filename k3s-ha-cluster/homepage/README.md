# Homepage

IaC dashboard for the homelab, configured entirely from
[`values.yaml`](values.yaml) — no UI, no database.

- Homepage (gethomepage.dev) via the `jameswynn/homepage` Helm chart
- Exposed at `home.yukselcloud.com` through Caddy (ClusterIP, no LB IP)
- Deploys via GitOps: `.forgejo/workflows/deploy-homepage.yml`
- Dashboard + widgets rendered server-side; config hot-reloads on push

## Layout

- `values.yaml` — everything: settings, service grid, widgets, k8s config
- `secret.yaml` — `HOMEPAGE_VAR_*` API-key *placeholders* (empty strings)

## Secrets: values live in the cluster, never in git

Widget keys are injected via the `homepage-secrets` Secret
(`envFrom` in the Helm values). Rules that keep keys out of the repo:

1. **Git holds placeholders only.** `secret.yaml` lists every
   `HOMEPAGE_VAR_*` name with an empty value. It exists so a fresh
   cluster gets all the keys it needs to start the pod.
2. **Real values are patched into the live Secret**, never edited in
   `secret.yaml`:

   ```bash
   kubectl -n homepage patch secret homepage-secrets --type merge -p \
     '{"stringData":{"HOMEPAGE_VAR_SONARR_API_KEY":"<key>"}}'
   ```

3. **The workflow never stomps them.** `Apply Secrets` in
   `deploy-homepage.yml` is *create-if-missing* — after the first install
   it skips applying the placeholder file, so live values survive every
   redeploy. (Don't "helpfully" change it back to `kubectl apply -f`.)

### Where each key comes from

| var | source |
| --- | --- |
| `HOMEPAGE_VAR_SONARR/_RADARR/_PROWLARR/_BAZARR_API_KEY` | the app's own API key, read from its `/config/config.xml` (in-cluster: `kubectl exec`) or Settings → General |
| `HOMEPAGE_VAR_NTFY_TOKEN` | **read**-permission ntfy access token — not the workflow's publish token (that one gets a 401 on the widget's long-poll) |

To add a new widget key: add the placeholder to `secret.yaml`, reference
`{{ HOMEPAGE_VAR_<NAME> }}` in `values.yaml`, then patch the real value
into the live Secret as above. The pod picks it up on the next Helm
upgrade (or `kubectl rollout restart deploy homepage`).

## Adding a service to the dashboard

Add a block to `config.services` in `values.yaml`:

```yaml
- My Service:
    href: https://service.yukselcloud.com
    icon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/service.png
    description: What it does
```

Push to `master`. The workflow runs `helm upgrade` and the pod reloads.
Links inside the dashboard are IaC too — this file is the source of truth.

## Access

`home.yukselcloud.com` sits behind Authelia `forward_auth` in
[`caddy/configmap.yaml`](../caddy/configmap.yaml). No `access_control` rule is
needed here — the existing `*.yukselcloud.com` / `group:infra` /
`one_factor` rule already matches, and the session cookie is scoped to the
apex domain.

The dashboard publishes the homelab's internal IPs, service names, ports and
node topology, so keep it behind auth. If Caddy ever needs a bypass for local
access, reach for Tailscale rather than reopening the route.

## Widget URLs must carry the Service port

Homepage proxies widgets server-side and silently falls back to `:80` when a
`url:` has no port. Most Services here do not listen on 80, so a missing port
shows up only as a red tile and `ETIMEDOUT` in the pod log.

After editing widget URLs, run:

```bash
python3 scripts/check-homepage-widgets.py
```

It cross-checks every `url:` in `values.yaml` against the live Service ports
and exits non-zero on a mismatch.

## Kubernetes integration

`mode: cluster` with `enableRbac: true` gives homepage read access for the
Kubernetes and Longhorn widgets (not service discovery — that reads Ingress
objects, which this cluster does not use; see the phase-2 marker-Ingress
issue).
