#!/usr/bin/env bash
# Runs ON ct254 (paperclip), piped in over SSH stdin by
# bootstrap-paperclip-lxc.sh. Expects TS_AUTHKEY, GIT_TOKEN,
# OPENCODE_SERVER_USERNAME, OPENCODE_SERVER_PASSWORD, OPENCODE_VERSION already
# exported by the caller.
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
  if [ ! -x "$PC_BIN" ]; then
    log "installing paperclipai (managed store, as $PC_HOME user)"
    su - paperclip -c 'npx --yes paperclipai install --yes' >/dev/null
  fi
  log "paperclipai version: $(su - paperclip -c "$PC_BIN --version")"
}

clone_homelab_repo() {
  # Verify GIT_TOKEN is a fine-grained token scoped to lab/homelab only, not
  # account-wide — it lives in plaintext in /root/.git-credentials below.
  log "cloning homelab repo"
  git config --global credential.helper store
  printf 'https://lab:%s@git.yukselcloud.com\n' "$GIT_TOKEN" > /root/.git-credentials
  chmod 600 /root/.git-credentials
  install -d "$PC_HOME/work"
  if [ ! -d "$PC_HOME/work/homelab/.git" ]; then
    git clone https://git.yukselcloud.com/lab/homelab.git "$PC_HOME/work/homelab"
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
    nft add rule inet paperclip input iifname "tailscale0" tcp dport 3100 accept
    nft add rule inet paperclip input iifname "eth0" tcp dport 3100 accept
    nft add rule inet paperclip input tcp dport 3100 drop
    log "firewalled :3100 to tailscale0 + LAN (eth0)"
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
  # ponytail: onboard is capped with a timeout because --yes starts the server
  # in the foreground once the config exists; systemd owns the process after
  # this. Re-running keeps the existing config by design.
  log "onboarding (non-interactive quickstart, 30s cap)"
  timeout 30 su - paperclip -c \
    "$PC_BIN onboard --yes --bind lan --no-install-service" >/dev/null 2>&1 || true
  su - paperclip -c "$PC_BIN allowed-hostname 192.168.0.54" >/dev/null 2>&1 || true
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
OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}
OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
ENVFILE
  chmod 0600 /etc/paperclip/paperclip.env

  systemctl daemon-reload
  systemctl enable paperclip
  # restart (not enable --now): re-runs here must pick up ExecStart changes
  systemctl restart paperclip
}

verify() {
  sleep 8
  log "service: $(systemctl is-active paperclip)"
  # Probe the LAN IP, not 127.0.0.1: the nft rule above drops non-eth0/
  # tailscale0 ingress, so a loopback probe would hang.
  log "http probe (LAN 192.168.0.54:3100): $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://192.168.0.54:3100/api/health || echo unreachable)"
  log "tailscale: $(tailscale ip -4 | head -1)"
  local claim
  claim="$(journalctl -u paperclip --no-pager 2>/dev/null | grep -o '/board-claim/[^ "]*' | tail -1 || true)"
  [ -n "$claim" ] && log "board claim URL: http://192.168.0.54:3100$claim"
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
write_systemd_unit
verify
