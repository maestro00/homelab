#!/usr/bin/env bash
# Runs ON ct254 (paperclip), piped in over SSH stdin by
# bootstrap-paperclip-lxc.sh. Expects TS_AUTHKEY, GIT_TOKEN and
# OPENCODE_VERSION already exported by the caller.
set -euo pipefail

log() { echo "[provision] $*"; }

PC_HOME="/srv/paperclip"
PC_BIN="$PC_HOME/.local/bin/paperclipai"

ensure_tools() {
  # The Ubuntu LXC template ships without curl/git — install them before
  # anything that fetches over HTTPS.
  if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    log "installing curl + git (missing from template)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl git >/dev/null
  fi
}

install_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    log "installing tailscale"
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  if ! tailscale status >/dev/null 2>&1; then
    log "joining tailnet"
    : "${TS_AUTHKEY:?joining the tailnet requires TS_AUTHKEY}"
    # --accept-dns=false: this tailnet has no custom nameservers, so MagicDNS
    # (100.100.100.100) can't resolve external hosts and breaks the installer.
    tailscale up --authkey="$TS_AUTHKEY" --hostname=paperclip-lxc --accept-dns=false
  fi
}

create_service_user() {
  if ! id -u paperclip >/dev/null 2>&1; then
    log "creating paperclip user"
    useradd -r -m -d "$PC_HOME" paperclip
  fi
}

install_node() {
  # Paperclip needs Node >= 24.11 (the Ubuntu 22.04 template ships none, and
  # the workstation's 22.11 is too old). NodeSource is the boring path.
  local major
  major="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/' || true)"
  if [ "${major:-0}" -lt 24 ]; then
    log "installing Node 24 from NodeSource"
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null
    apt-get install -y -qq nodejs >/dev/null
  fi
  log "node version: $(node --version)"
}

install_gateway_auth() {
  if [ -f /root/.local/share/opencode/auth.json ]; then
    install -d -o paperclip -g paperclip "$PC_HOME/.local/share/opencode"
    install -o paperclip -g paperclip -m 0600 \
      /root/.local/share/opencode/auth.json \
      "$PC_HOME/.local/share/opencode/auth.json"
    # install -d creates missing parents as root, and opencode (bun) creates
    # $HOME/.local/state at startup. Root-owned .local makes every
    # `opencode --version` exit 1, which silently fails paperclip's bundled
    # opencode postinstall with a misleading EBADPLATFORM error.
    chown -R paperclip:paperclip "$PC_HOME/.local"
    log "gateway auth installed"
  fi
}

install_opencode() {
  if [ ! -x /opt/opencode/bin/opencode ]; then
    log "installing opencode $OPENCODE_VERSION (native installer)"
    curl -fsSL https://opencode.ai/install | bash -s -- --version "$OPENCODE_VERSION" --no-modify-path
    # installer puts the binary in the running user's home; move to /opt
    [ -d /root/.opencode ] && mv /root/.opencode /opt/opencode
    chmod -R 755 /opt/opencode
    ln -sf /opt/opencode/bin/opencode /usr/local/bin/opencode
  fi
  log "opencode version: $(/usr/local/bin/opencode --version)"
}

install_paperclip() {
  # The launcher in .local/bin outlives a wiped ~/.paperclip, but its payload
  # (cli/current/node_modules/paperclipai) does not — so -x is not proof the
  # CLI works. Ask the CLI itself.
  if ! su - paperclip -c "$PC_BIN --version" >/dev/null 2>&1; then
    log "installing paperclipai (managed store, as $PC_HOME user)"
    su - paperclip -c 'npx --yes paperclipai install --yes' >/dev/null
  fi
  log "paperclipai version: $(su - paperclip -c "$PC_BIN --version")"
}

clone_homelab_repo() {
  # Verify GIT_TOKEN is a fine-grained token scoped to lab/homelab only, not
  # account-wide — it lives in plaintext in /root/.git-credentials below.
  # shortcut: agents run as `paperclip` and cannot read that store, so the
  # workspace is read-only to them by design; per-agent tokens are #64 work.
  log "cloning homelab repo"
  git config --global credential.helper store
  printf 'https://lab:%s@git.yukselcloud.com\n' "$GIT_TOKEN" > /root/.git-credentials
  chmod 600 /root/.git-credentials
  install -d "$PC_HOME/work"
  if [ ! -d "$PC_HOME/work/homelab/.git" ]; then
    git clone https://git.yukselcloud.com/lab/homelab.git "$PC_HOME/work/homelab"
  else
    # The agents work from this clone. A stale one means they cannot see the
    # code they are being asked to reason about. The tree is paperclip-owned
    # from the chown below, so git needs the exception for a root pull.
    git -c safe.directory="$PC_HOME/work/homelab" \
      -C "$PC_HOME/work/homelab" pull --ff-only >/dev/null \
      || log "pull failed — workspace is stale"
  fi
  chown -R paperclip:paperclip "$PC_HOME/work"
}

install_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log "installing kubectl"
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
  fi
  # One kubeconfig per agent: ops is read-only, deploy is namespace-scoped.
  # Missing files are fine — that agent simply starts without cluster access.
  install -d -o paperclip -g paperclip "$PC_HOME/.kube"
  local name
  for name in ops-config deploy-config; do
    if [ -f "/root/.kube/$name" ]; then
      install -o paperclip -g paperclip -m 0600 "/root/.kube/$name" "$PC_HOME/.kube/$name"
      log "kubeconfig staged: $name"
    fi
  done
}

restrict_port() {
  # :3100 only from Tailscale and the LAN (eth0); drop everything else.
  # LAN access is behind Paperclip's own login, Tailscale access by the
  # tailnet itself — this firewall is defense in depth for both.
  if command -v nft >/dev/null 2>&1; then
    nft list table inet paperclip >/dev/null 2>&1 || nft add table inet paperclip
    nft list chain inet paperclip input >/dev/null 2>&1 || \
      nft add chain inet paperclip input '{ type filter hook input priority 0; }'
    nft flush chain inet paperclip input
    nft add rule inet paperclip input iifname "lo" tcp dport 3100 accept
    nft add rule inet paperclip input iifname "tailscale0" tcp dport 3100 accept
    nft add rule inet paperclip input iifname "eth0" tcp dport 3100 accept
    # Paperclip falls back to :3101 when :3100 is taken. Without this the
    # fallback port — serving an active board-claim invite — is reachable
    # from anywhere routable to the host, because the chain policy is accept.
    nft add rule inet paperclip input tcp dport { 3100-3110 } drop
    log "firewalled :3100 to lo + tailscale0 + LAN, :3101-3110 dropped"
  else
    log "nft not available — skipping firewall rule, relying on the login only"
  fi
}

enable_persistent_logging() {
  # Keeps Paperclip's log across reboots, so an agent action can be
  # reconstructed after the fact rather than lost at the next reboot.
  mkdir -p /var/log/journal
  systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
}

onboard() {
  # Required: `paperclipai run` self-onboards only when it has a TTY, and under
  # systemd it exits with "No config found and terminal is non-interactive".
  # The trap is that --yes also starts a server and detaches it (PPID 1), which
  # `timeout` cannot reap — that orphan held :3100 for five days while the unit
  # silently fell back to :3101. Reap by user, then hand the port to systemd.
  log "onboarding (non-interactive quickstart)"
  timeout 90 su - paperclip -c \
    "$PC_BIN onboard --yes --bind lan --no-install-service" >/dev/null 2>&1 || true
  pkill -u paperclip 2>/dev/null || true
  sleep 3
  pkill -9 -u paperclip 2>/dev/null || true
  local cfg="$PC_HOME/.paperclip/instances/default/config.json"
  for _ in $(seq 1 15); do
    [ -f "$cfg" ] && break
    sleep 2
  done
  [ -f "$cfg" ] || { log "FAILED: onboard wrote no config.json"; exit 1; }
  log "instance configured"
}

allow_lan_hostname() {
  # Needs config.json, so it runs after onboard. The unit starts after this and
  # reads the allowlist on its first boot; no restart dance.
  log "allowing the LAN IP in the hostname allowlist"
  su - paperclip -c "$PC_BIN allowed-hostname 192.168.0.54" >/dev/null
}

write_systemd_unit() {
  # Binds 0.0.0.0: served on both the LAN IP (192.168.0.54) and the Tailscale
  # IP (100.x). The nft rule above drops :3100 on any other interface.
  # ponytail: hand-written unit instead of 'paperclipai service install' —
  # that path needs user systemd + lingering; revisit if we want its
  # update/status plumbing.
  log "writing systemd unit (binding 0.0.0.0: LAN + Tailscale)"

  cat > /etc/systemd/system/paperclip.service <<UNIT
[Unit]
Description=Paperclip Agent Orchestrator
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
User=paperclip
Group=paperclip
WorkingDirectory=$PC_HOME
EnvironmentFile=/etc/paperclip/paperclip.env
# The SQL dumps in .paperclip/instances/default/data/backups contain every
# agent output and secret ref value; default umask made them world-readable.
UMask=0077
ExecStart=$PC_BIN run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  install -d -m 0750 /etc/paperclip
  cat > /etc/paperclip/paperclip.env <<ENVFILE
HOST=0.0.0.0
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
PAPERCLIP_AUTH_BASE_URL_MODE=auto
ENVFILE
  # No OPENCODE_SERVER_USERNAME/PASSWORD here on purpose: those guard ct253's
  # `opencode serve` on :4096. ct254 runs no opencode server, and anything in
  # this file lands in the agent child's environment, the board database and
  # its hourly SQL dumps.
  chmod 0600 /etc/paperclip/paperclip.env

  systemctl daemon-reload
  systemctl enable paperclip
  # restart (not enable --now): re-runs here must pick up ExecStart changes
  systemctl restart paperclip
}

verify() {
  local code=""
  # A fresh instance needs ~30s to create its embedded database before it
  # binds; a fixed sleep either races the startup or wastes a minute.
  for _ in $(seq 1 12); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      http://192.168.0.54:3100/api/health || true)"
    [ "$code" = "200" ] && break
    sleep 5
  done
  log "service: $(systemctl is-active paperclip)"
  log "tailscale: $(tailscale ip -4 | head -1)"
  log "http probe (LAN 192.168.0.54:3100): ${code:-000}"
  # A 403 here means an orphaned detached server owns :3100 and the unit fell
  # back to :3101. That passed silently for five days; fail the run instead.
  if [ "${code:-000}" != "200" ]; then
    log "FAILED: :3100 answered ${code:-000}, expected 200"
    log "runners: $(pgrep -af 'index.js' | tr '\n' ' ')"
    exit 1
  fi
  # The bootstrap invite is an admin credential, so it is never echoed here —
  # it is already in the journal, and printing it again only spreads the copy.
  if journalctl -u paperclip --no-pager 2>/dev/null | \
      grep -qE '/invite/pcp_bootstrap_|/board-claim/'; then
    log "board is UNCLAIMED. Read the invite URL from the container journal:"
    log "  journalctl -u paperclip | grep -m1 'Invite URL'"
  else
    log "no bootstrap invite in the journal — board already claimed"
  fi
}

ensure_tools
install_tailscale
create_service_user
install_node
install_gateway_auth
install_opencode
install_paperclip
clone_homelab_repo
install_kubectl
restrict_port
enable_persistent_logging
onboard
allow_lan_hostname
write_systemd_unit
verify
