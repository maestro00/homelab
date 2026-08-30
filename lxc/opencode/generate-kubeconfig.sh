#!/usr/bin/env bash
# Build a scoped kubeconfig for the opencode-agent ServiceAccount from its
# token Secret + the cluster CA. Run from a machine with kubectl access,
# after applying manifests/*.yaml.
#
# Usage:
#   ./generate-kubeconfig.sh > opencode-agent.kubeconfig

set -euo pipefail

NAMESPACE="opencode-agent"
SECRET_NAME="opencode-agent-token"
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
: "${TOKEN:?token never populated — check the Secret exists (kubectl apply -f manifests/opencode-agent/token-secret.yaml) and retry}"

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
  - name: opencode-agent@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      namespace: ${NAMESPACE}
      user: opencode-agent
current-context: opencode-agent@${CLUSTER_NAME}
users:
  - name: opencode-agent
    user:
      token: ${TOKEN}
KUBECONFIG

log "kubeconfig written to stdout — verify with: KUBECONFIG=<file> kubectl auth can-i --list"
