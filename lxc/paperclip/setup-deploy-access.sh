#!/usr/bin/env bash
# Give the `deploy` agent on ct254 a write path to lab/homelab, narrowly.
#
# Run from the workstation, after the board is claimed and the repo pushed:
#   FORGEJO_TOKEN=... ./lxc/paperclip/setup-deploy-access.sh
#
# Why a deploy key and not a Forgejo token: tokens are restricted by *scope*,
# not by repository, and the `lab` account owns the org. A token handed to an
# agent would let it write every repo `lab` can reach, and a push to master
# triggers Forgejo Actions that apply manifests to the cluster with the
# runner's kubectl — a leaked token would be a cluster-level compromise.
# A deploy key is bound to one repository, and `read_write` is granted only
# here. It lives as a 0600 file on ct254: never in git, never in the Paperclip
# database or its hourly SQL dumps, never in a process argument list.
#
# The key can push branches and nothing else. PRs are opened and merged by a
# human; deploy only proposes.
#
# Idempotent: re-running reuses the existing key and remote.

set -euo pipefail

CT_HOST="${CT_HOST:-root@192.168.0.54}"
FORGEJO_URL="${FORGEJO_URL:-https://git.yukselcloud.com}"
FORGEJO_HOST="${FORGEJO_URL#https://}"
REPO="${REPO:-lab/homelab}"
KEY_TITLE="${KEY_TITLE:-paperclip-ct254}"
WS="/srv/paperclip/work/homelab"

: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN (the lab account token, gitignored)}"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

log() { echo "[deploy-access] $*"; }
die() { echo "[deploy-access] FAILED: $*" >&2; exit 1; }

# 1. Key pair on the container, owned by the agent's own user.
log "ensuring a deploy keypair exists on ct254"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c '
  install -d -m 0700 ~/.ssh
  [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N \"\" \
    -C paperclip-ct254 -f ~/.ssh/id_ed25519
  chmod 0600 ~/.ssh/id_ed25519
'"

PUBKEY="$("${SSH[@]}" "$CT_HOST" "su - paperclip -c 'cat ~/.ssh/id_ed25519.pub'")"
[ -n "$PUBKEY" ] || die "no public key came back from ct254"
log "public key: $(cut -d' ' -f1-2 <<<"$PUBKEY")"

# Host key trust: pin the real fingerprint rather than disabling checking.
log "caching the Forgejo host key"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c '
  grep -q \"^${FORGEJO_HOST} \" ~/.ssh/known_hosts 2>/dev/null || \
    ssh-keyscan -t ed25519 ${FORGEJO_HOST} >> ~/.ssh/known_hosts
'"

# 2. Register the key on the repo, only if it is not already there.
KEY_EXISTS=$(curl -sS -m 20 "$FORGEJO_URL/api/v1/repos/$REPO/keys" \
  -H "Authorization: token $FORGEJO_TOKEN" \
  | python3 -c '
import json,sys
want=sys.argv[1].split(" ",2)[:2]
for k in json.load(sys.stdin):
    if k.get("key","").split(" ",2)[:2] == want:
        print("yes"); break
' "$PUBKEY")

if [ "$KEY_EXISTS" = "yes" ]; then
  log "deploy key already registered on $REPO — skipping"
else
  log "registering the deploy key on $REPO (read_write)"
  curl -sS -m 20 -X POST "$FORGEJO_URL/api/v1/repos/$REPO/keys" \
    -H "Authorization: token $FORGEJO_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c '
import json,sys
print(json.dumps({"title":sys.argv[1],"key":sys.argv[2],"read_write":True}))
' "$KEY_TITLE" "$PUBKEY")" >/dev/null
  log "deploy key registered"
fi

# 3. A separate `deploy` remote. origin stays HTTPS so the root-side refresh
#    in remote-provision.sh keeps working untouched.
log "adding the ssh deploy remote to the workspace clone"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c '
  cd $WS
  git config --global --add safe.directory $WS
  git remote remove deploy 2>/dev/null || true
  git remote add deploy git@${FORGEJO_HOST}:$REPO.git
  git config user.name  \"paperclip-deploy\"
  git config user.email \"paperclip@yukselcloud.com\"
'"

log "verifying the key can reach the repo"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c \
  \"cd $WS && git fetch --quiet deploy && git rev-parse --short deploy/master\"" \
  || die "fetch over the deploy key failed — check the key was accepted"

# 4. Refresh origin so the agents read current code.
log "refreshing origin as root (HTTPS credentials stay root-only)"
"${SSH[@]}" "$CT_HOST" "git -c safe.directory=$WS -C $WS pull --ff-only -q origin master \
  && chown -R paperclip:paperclip $WS" \
  || log "origin pull failed — provisioning refresh will catch it up"

log "workspace now at:"
"${SSH[@]}" "$CT_HOST" "su - paperclip -c 'cd $WS && git log --oneline -1'"

cat <<DONE

[done] deploy has a one-repo push path.

  remote   deploy -> git@${FORGEJO_HOST}:$REPO.git (ssh deploy key, read_write)
  key      ct254:~paperclip/.ssh/id_ed25519 (0600, never left the container)
  origin   HTTPS, refreshed by root during provisioning

  Next: hire the agent from lxc/paperclip/agents/deploy.agent.json
DONE
