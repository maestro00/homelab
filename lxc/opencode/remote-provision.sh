#!/usr/bin/env bash
# Runs ON ct53, piped in over SSH stdin by bootstrap-opencode-lxc.sh.
# Expects TS_AUTHKEY, GIT_TOKEN, OPENCODE_SERVER_USERNAME,
# OPENCODE_SERVER_PASSWORD, OPENCODE_VERSION already exported by the caller.
set -euo pipefail

log() { echo "[provision] $*"; }

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
    tailscale up --authkey="$TS_AUTHKEY" --hostname=opencode-lxc --accept-dns=false
  fi
}

create_service_user() {
  if ! id -u opencode >/dev/null 2>&1; then
    log "creating opencode user"
    useradd -r -m -d /srv/opencode opencode
  fi
}

install_gateway_auth() {
  if [ -f /root/.local/share/opencode/auth.json ]; then
    install -d -o opencode -g opencode /srv/opencode/.local/share/opencode
    install -o opencode -g opencode -m 0600 \
      /root/.local/share/opencode/auth.json \
      /srv/opencode/.local/share/opencode/auth.json
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

clone_homelab_repo() {
  # Verify GIT_TOKEN is a fine-grained token scoped to lab/homelab only, not
  # account-wide — it lives in plaintext in /root/.git-credentials below.
  log "cloning homelab repo"
  git config --global credential.helper store
  printf 'https://lab:%s@git.yukselcloud.com\n' "$GIT_TOKEN" > /root/.git-credentials
  chmod 600 /root/.git-credentials
  if [ ! -d /srv/opencode/homelab/.git ]; then
    git clone https://git.yukselcloud.com/lab/homelab.git /srv/opencode/homelab
  fi
  chown -R opencode:opencode /srv/opencode/homelab
}

install_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log "installing kubectl"
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
  fi
  if [ -f /root/.kube/config ]; then
    install -d -o opencode -g opencode /srv/opencode/.kube
    cp /root/.kube/config /srv/opencode/.kube/config
    chown opencode:opencode /srv/opencode/.kube/config
  fi
}

restrict_port() {
  # :4096 only from Tailscale and the LAN (eth0); drop everything else.
  # LAN access is gated by HTTP basic auth (opencode.env), Tailscale access
  # by the tailnet itself — this firewall is defense in depth for both.
  if command -v nft >/dev/null 2>&1; then
    nft list table inet opencode >/dev/null 2>&1 || nft add table inet opencode
    nft list chain inet opencode input >/dev/null 2>&1 || \
      nft add chain inet opencode input '{ type filter hook input priority 0; }'
    nft flush chain inet opencode input
    nft add rule inet opencode input iifname "tailscale0" tcp dport 4096 accept
    nft add rule inet opencode input iifname "eth0" tcp dport 4096 accept
    nft add rule inet opencode input tcp dport 4096 drop
    log "firewalled :4096 to tailscale0 + LAN (eth0)"
  else
    log "nft not available — skipping firewall rule, relying on basic auth only"
  fi
}

enable_persistent_logging() {
  # Keeps opencode's session log across reboots, so a remotely-triggered
  # action is reconstructable after the fact rather than lost at next reboot.
  mkdir -p /var/log/journal
  systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
}

write_systemd_unit() {
  # Binds 0.0.0.0: served on both the LAN IP (192.168.0.53) and the Tailscale
  # IP (100.x). The nft rule above drops :4096 on any other interface.
  log "writing systemd unit (binding 0.0.0.0: LAN + Tailscale)"

  cat > /etc/systemd/system/opencode.service <<UNIT
[Unit]
Description=OpenCode Always-On Server
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
User=opencode
Group=opencode
WorkingDirectory=/srv/opencode/homelab
EnvironmentFile=/etc/opencode/opencode.env
ExecStart=/usr/local/bin/opencode serve --hostname 0.0.0.0 --port 4096
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  install -d -m 0750 /etc/opencode
  cat > /etc/opencode/opencode.env <<ENVFILE
OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}
OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}
OPENCODE_DISABLE_DEFAULT_PLUGINS=1
ENVFILE
  chmod 0600 /etc/opencode/opencode.env

  systemctl daemon-reload
  systemctl enable opencode
  # restart (not enable --now): re-runs here must pick up ExecStart changes
  systemctl restart opencode
}

verify() {
  sleep 3
  log "service: $(systemctl is-active opencode)"
  # Probe the LAN IP, not 127.0.0.1: the nft rule above drops non-eth0/
  # tailscale0 ingress, so a loopback probe would hang (no --max-time).
  log "http probe (LAN 192.168.0.53:4096): $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://192.168.0.53:4096/ || echo unreachable)"
  log "tailscale: $(tailscale ip -4 | head -1)"
}

ensure_tools
install_tailscale
create_service_user
install_gateway_auth
install_opencode
clone_homelab_repo
install_kubectl
restrict_port
enable_persistent_logging
write_systemd_unit
verify
