#!/usr/bin/env bash
# Give the `deploy` agent on ct254 a write path to lab/homelab, narrowly.
#
# Run from the workstation, after the board is claimed and the repo pushed:
#   FORGEJO_TOKEN=... ./lxc/paperclip/setup-deploy-access.sh
#
# Forgejo here is reached over HTTPS only — `forgejo-ssh` is a ClusterIP with
# no LoadBalancer, and port 22 at the public IP is the router's dropbear, not
# Forgejo. A token for the `lab` account would reach all three of its repos
# (homelab, telegram-agent, homelab-event-collector), including ones whose
# pushes trigger deploy workflows. Instead this creates a dedicated bot user
# that is a write collaborator on lab/homelab and nothing else, so its
# credential is limited by membership — the only real per-repo scoping Forgejo
# offers.
#
# The credential is the bot's password over HTTPS basic auth. Forgejo 14 has no
# self-service token API, and the admin token-creation route demands basic auth
# of an admin; the password path is identical in scope here because the bot has
# write on exactly one repo and no admin rights.
#
# The password never appears on stdout or in git: it is generated, delivered to
# ct254 as a 0600 file, and deleted from the workstation. It reaches the board
# database only if an agent pastes it, which deploy.md forbids and the dump
# audit checks.
#
# The bot can push branches and open PRs (issue scope). Merging is a human
# action.
#
# Idempotent: user and collaborator steps are idempotent; each run resets the
# password and overwrites the credential file.

set -euo pipefail

CT_HOST="${CT_HOST:-root@192.168.0.54}"
FORGEJO_URL="${FORGEJO_URL:-https://git.yukselcloud.com}"
API="$FORGEJO_URL/api/v1"
REPO="${REPO:-lab/homelab}"
BOT="${BOT:-paperclip-deploy}"
BOT_EMAIL="${BOT_EMAIL:-paperclip@yukselcloud.com}"
WS="/srv/paperclip/work/homelab"

: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN (the lab account admin token, gitignored)}"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
AUTH=(-H "Authorization: token $FORGEJO_TOKEN")

log() { echo "[deploy-access] $*"; }
die() { echo "[deploy-access] FAILED: $*" >&2; exit 1; }

# 1. Bot user, if it does not exist.
if curl -sS -m 20 "$API/users/$BOT" "${AUTH[@]}" -o /dev/null -w '%{http_code}' | grep -q 200; then
  log "bot user $BOT already exists"
else
  log "creating bot user $BOT"
  curl -sS -m 20 -X POST "$API/admin/users" "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c '
import json,sys,secrets
print(json.dumps({
  "username": sys.argv[1], "email": sys.argv[2],
  "password": secrets.token_urlsafe(24), "must_change_password": False,
  "login_name": sys.argv[1], "send_notify": False,
}))' "$BOT" "$BOT_EMAIL")" -o /dev/null || die "user creation failed"
  log "bot user created"
fi

# 2. Collaborator on lab/homelab with write, if not already.
if curl -sS -m 20 "$API/repos/$REPO/collaborators/$BOT" "${AUTH[@]}" -o /dev/null -w '%{http_code}' | grep -q 204; then
  log "bot is already a collaborator on $REPO"
else
  log "adding bot as write collaborator on $REPO"
  curl -sS -m 20 -X PUT "$API/repos/$REPO/collaborators/$BOT" "${AUTH[@]}" \
    -H "Content-Type: application/json" -d '{"permission":"write"}' -o /dev/null \
    || die "collaborator add failed"
fi

# 3. A password for the bot, kept only long enough to reach the container.
BOTPW="$(openssl rand -hex 24)"
curl -sS -m 20 -X PATCH "$API/admin/users/$BOT" "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c '
import json,sys
print(json.dumps({"password": sys.argv[1]}))
' "$BOTPW")" -o /dev/null || die "password reset failed"

TMP=$(mktemp)
chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$BOTPW" > "$TMP"
log "delivering the bot credential to ct254 (0600, paperclip-owned)"

scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "$TMP" "$CT_HOST:/root/deploy-pass"
"${SSH[@]}" "$CT_HOST" "bash -s" <<INNER
set -euo pipefail
BOT='$BOT'
PASS=\$(cat /root/deploy-pass)
rm -f /root/deploy-pass
install -d -o paperclip -g paperclip -m 0750 /srv/paperclip/.config
printf 'https://%s:%s@git.yukselcloud.com\n' "\$BOT" "\$PASS" \
  > /srv/paperclip/.config/git-credentials
chown paperclip:paperclip /srv/paperclip/.config/git-credentials
chmod 0600 /srv/paperclip/.config/git-credentials
su - paperclip -c '
  git config --global credential.helper "store --file \$HOME/.config/git-credentials"
  cd /srv/paperclip/work/homelab
  git remote remove deploy 2>/dev/null || true
  git remote add deploy https://git.yukselcloud.com/lab/homelab.git
  git config user.name  paperclip-deploy
  git config user.email paperclip@yukselcloud.com
'
INNER

# 4. The workspace is refreshed as root during provisioning, which leaves
#    .git/objects root-owned; a paperclip-side fetch cannot write there.
log "handing the workspace to the agent user"
"${SSH[@]}" "$CT_HOST" "chown -R paperclip:paperclip $WS"

# 5. Prove the bot can read the repo (cheap, non-mutating).
log "verifying the bot credential works"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c \
  'cd $WS && git fetch --quiet deploy && git rev-parse --short deploy/master'" \
  || die "fetch with the bot credential failed"

cat <<DONE

[done] deploy has a single-repo write path.

  user     $BOT (write collaborator on $REPO only)
  cred     HTTPS basic auth, stored 0600 on ct254
  remote   deploy -> https://git.yukselcloud.com/lab/homelab.git
  merge    not granted; PRs open, humans merge

  Next: hire the agent from lxc/paperclip/agents/deploy.agent.json
DONE
