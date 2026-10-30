#!/usr/bin/env bash
# Build a scoped kubeconfig for one Paperclip agent ServiceAccount from its
# token Secret + the cluster CA. Run from a machine with kubectl access,
# after applying manifests/paperclip-agent/*.yaml.
#
# Usage:
#   ./generate-kubeconfig.sh ops    > ../../temp/paperclip-ops.kubeconfig
#   ./generate-kubeconfig.sh deploy > ../../temp/paperclip-deploy.kubeconfig
#
# Those two paths are what bootstrap-paperclip-lxc.sh looks for.

set -euo pipefail

NAMESPACE="paperclip-agent"
AGENT="${1:-}"

case "$AGENT" in
  ops|deploy) ;;
  *)
    echo "usage: $0 ops|deploy > <file>" >&2
    exit 64
    ;;
esac

SECRET_NAME="${AGENT}-token"
CLUSTER_NAME="${CLUSTER_NAME:-yukselcloud}"
API_SERVER="${API_SERVER:-https://192.168.0.100:6443}"  # kube-vip VIP

log() { echo "[generate-kubeconfig] $*" >&2; }

# The token controller populates the Secret asynchronously — poll briefly
# rather than failing on the very first check right after `kubectl apply`.
TOKEN=""
for _ in $(seq 1 10); do
  TOKEN="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" \
    -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)"
  [ -n "$TOKEN" ] && break
  log "waiting for token controller to populate $SECRET_NAME..."
  sleep 2
done
: "${TOKEN:?token never populated — apply manifests/paperclip-agent/token-secrets.yaml and retry}"

CA_CERT="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.ca\.crt}')"
: "${CA_CERT:?ca.crt missing from $SECRET_NAME}"

cat <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${API_SERVER}
      certificate-authority-data: ${CA_CERT}
contexts:
  - name: ${AGENT}@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      namespace: ${NAMESPACE}
      user: ${AGENT}
current-context: ${AGENT}@${CLUSTER_NAME}
users:
  - name: ${AGENT}
    user:
      token: ${TOKEN}
KUBECONFIG

log "kubeconfig written to stdout — verify with: KUBECONFIG=<file> kubectl auth can-i --list"
