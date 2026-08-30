#!/usr/bin/env bash
# Bootstrap the always-on opencode server inside the LXC container (ct 253,
# lab-pve2) created by Terraform. Installer of choice: native installer
# (real Bun binary) instead of the npm SEA wrapper that failed on kernel 5.15.
#
# Run from the workstation after `terraform apply`:
#   TS_AUTHKEY=... GIT_TOKEN=... \
#   OPENCODE_SERVER_USERNAME=... OPENCODE_SERVER_PASSWORD=... \
#   ./lxc/opencode/bootstrap-opencode-lxc.sh
#
# opencode gateway auth (default free models like big-pickle) is copied
# automatically from $HOME/.local/share/opencode/auth.json — no API key
# needed.
#
# Idempotent: safe to re-run.
#
# Secrets are piped to the remote host over SSH stdin, never embedded in a
# command line — a command-line arg is visible to any local user on ct53 via
# `ps auxww` for as long as the process runs; stdin isn't.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_PROVISION_SCRIPT="$SCRIPT_DIR/remote-provision.sh"

CT_HOST="${CT_HOST:-root@192.168.0.53}"
OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.25}"

: "${TS_AUTHKEY:?set TS_AUTHKEY (fresh key from the Tailscale console)}"
: "${GIT_TOKEN:?set GIT_TOKEN (Forgejo token — verify it is scoped to lab/homelab only, not account-wide)}"
: "${OPENCODE_SERVER_USERNAME:?set OPENCODE_SERVER_USERNAME (web basic auth)}"
: "${OPENCODE_SERVER_PASSWORD:?set OPENCODE_SERVER_PASSWORD (web basic auth)}"

# Default to the scoped opencode-agent ServiceAccount kubeconfig generated
# by generate-kubeconfig.sh (see manifests/opencode-agent).
# Override with your full kubeconfig only if the scoped one is unavailable
# (e.g. fresh workloads outside media/monitoring need it — intentionally rare).
KUBECONFIG_SRC="${KUBECONFIG_SRC:-$SCRIPT_DIR/../../temp/opencode-agent.kubeconfig}"
AUTH_SRC="${AUTH_SRC:-$HOME/.local/share/opencode/auth.json}"

log() { echo "[bootstrap] $*"; }

push_kubeconfig() {
  if [ -f "$KUBECONFIG_SRC" ]; then
    ssh -o BatchMode=yes "$CT_HOST" 'mkdir -p /root/.kube'
    scp -q -o BatchMode=yes "$KUBECONFIG_SRC" "$CT_HOST:/root/.kube/config"
    log "kubeconfig copied ($KUBECONFIG_SRC)"
  else
    log "no kubeconfig at $KUBECONFIG_SRC — skipping cluster management setup"
  fi
}

push_opencode_auth() {
  if [ -f "$AUTH_SRC" ]; then
    ssh -o BatchMode=yes "$CT_HOST" 'install -d /root/.local/share/opencode'
    scp -q -o BatchMode=yes "$AUTH_SRC" "$CT_HOST:/root/.local/share/opencode/auth.json"
    log "opencode gateway auth staged for the service user"
  else
    log "no auth.json at $AUTH_SRC — run 'opencode auth login' on the workstation first"
  fi
}

provision_remote() {
  log "running remote provisioning script"
  # %q shell-quotes each value so tokens with special characters survive the
  # round trip intact; the whole block is piped over stdin, so none of this
  # ever appears as a ct53 process argument.
  {
    printf 'export OPENCODE_VERSION=%q\n' "$OPENCODE_VERSION"
    printf 'export TS_AUTHKEY=%q\n' "$TS_AUTHKEY"
    printf 'export GIT_TOKEN=%q\n' "$GIT_TOKEN"
    printf 'export OPENCODE_SERVER_USERNAME=%q\n' "$OPENCODE_SERVER_USERNAME"
    printf 'export OPENCODE_SERVER_PASSWORD=%q\n' "$OPENCODE_SERVER_PASSWORD"
    cat "$REMOTE_PROVISION_SCRIPT"
  } | ssh -o BatchMode=yes "$CT_HOST" bash -s
}

push_kubeconfig
push_opencode_auth
provision_remote

TS_IP="$(ssh -o BatchMode=yes "$CT_HOST" 'tailscale ip -4' | head -1)"
echo "[done] opencode LXC bootstrapped. Reach it at http://${TS_IP}:4096 via Tailscale."
