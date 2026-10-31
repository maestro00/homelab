# Paperclip — ct254

Agent orchestrator on `lab-pve1`: 4 CPU, 4096 MB with 2048 MB swap, 32 GB on
`local-lvm`, board on `http://192.168.0.54:3100` from the LAN and the tailnet.
Never proxied — no Caddy route, no Authelia.

Paperclip spawns `opencode run` as a subprocess on this box. It is not the
interactive opencode server on ct253 and does not talk to it.

## Provision

```bash
terraform -chdir=terraform apply -var-file=node.tfvars -var-file=../temp/proxmox.tfvars
kubectl apply -f lxc/paperclip/manifests/paperclip-agent/
./lxc/paperclip/generate-kubeconfig.sh ops    > ../temp/paperclip-ops.kubeconfig
./lxc/paperclip/generate-kubeconfig.sh deploy > ../temp/paperclip-deploy.kubeconfig
GIT_TOKEN=... ./bootstrap-paperclip-lxc.sh
```

`TS_AUTHKEY` is only needed if the container has not joined the tailnet. Node
24 and the `opencode` 1.18.25 pin are installed by the remote script.

## Claim the board — human only

First boot prints an admin invite to the journal. The scripts deliberately do
not echo it, so read it on the box and open it from the LAN:

```bash
ssh root@192.168.0.54 "journalctl -u paperclip | grep -m1 'Invite URL'"
```

Signing up on that instance **is** the claim: accounts live in ct254's own
embedded Postgres. There is no Paperclip-hosted account and no upstream
sign-up. `disableSignUp` is false, so claim it before anything else shares the
LAN — whoever registers first becomes admin.

## Drive it from the CLI

The credential store is keyed by `api-base`, so a `whoami` without the same
base the login used reports `401` even when you are approved. Set the defaults
once:

```bash
su - paperclip -c 'paperclipai auth login --no-browser'   # prints an approval URL
su - paperclip -c 'paperclipai context set --api-base http://127.0.0.1:3100 \
  --company-id <id> --persona board'
```

The approval URL prints as `127.0.0.1`; open it with the LAN host instead.
`issue create` ignores the context default and needs `-C <companyId>`.

## Agents

Definitions live in `agents/` as payloads, applied from the workspace clone:

```bash
su - paperclip -c "paperclipai agent create \
  --payload-json \"\$(cat /srv/paperclip/work/homelab/lxc/paperclip/agents/ops.agent.json)\""
```

| Agent | Adapter | Model | Cluster power |
| ----- | ------- | ----- | ------------- |
| `ops` | `opencode_local` | `opencode/big-pickle` | `view`, cluster-wide, no Secrets |

No Paperclip-side provider key is involved: `model` is an opencode id resolved
by opencode's own auth on this box, so the web wizard's Claude/OpenAI step is
not on this path.

`runtimeConfig.heartbeat.enabled` defaults to `false` — a new agent cannot run
or spend on its own. Assigning an issue still wakes it (`invocationSource:
assignment`); only timer wakes are off.

> `dangerouslySkipPermissions` defaults to `true` for unattended runs, so
> opencode gets `permission=allow` and will not prompt. The guardrail is the
> scoped kubeconfig, not an approval dialog.

## Secrets

- Nothing secret in the EnvironmentFile or in `adapterConfig.env` — that env
  reaches the agent child, the database and its hourly SQL dumps, and API
  responses only *redact* it rather than withhold it.
- Backups are service-created under `UMask=0077` (dir `0750`, dumps `0600`). A
  manual `paperclipai db:backup` runs under the login umask and lands group
  readable — `chmod 600` it.
- The agent can read its own `auth.json`; opencode needs that to run. That
  credential is personal Copilot OAuth today, which is #64 work to replace.
- Verify with a dump grep that no credential *value* reached the database.

## Check

```bash
curl -s http://192.168.0.54:3100/api/health          # status ok, 200
ssh root@192.168.0.54 'ss -ltnp | grep -c :3100'     # exactly 1
ssh root@192.168.0.54 'nft list table inet paperclip'
```

A 403 on `:3100` means an orphaned `onboard` server is back: `paperclipai
onboard --yes` detaches its server and `timeout` cannot reap it, so the unit
falls back to `:3101`. `verify()` in the remote script fails the run on
anything other than 200.
