#!/bin/sh
set -euo pipefail

if [ -z "${NTFY_TOKEN:-}" ] || \
   [ -z "${NTFY_TOPIC:-}" ] || \
   [ -z "${NTFY_URL:-}" ] || \
   [ -z "${NODE_NAME:-}" ]; then
  echo "Missing required environment variables: NTFY_TOKEN, NTFY_TOPIC, NTFY_URL, NODE_NAME" >&2
  exit 1
fi

while true; do
  DF_OUTPUT=$(df -P /host | awk 'NR==2 {
    total_kb = $2
    used_kb = $3
    pct = $5
    gsub(/%/, "", pct)
    total_gb = total_kb / 1048576
    used_gb = used_kb / 1048576
    printf "%.2f %.2f %d", total_gb, used_gb, pct
  }')

  if [ -z "$DF_OUTPUT" ]; then
    echo "unable to read disk usage" >&2
    exit 1
  fi

  TOTAL_GB=$(echo "$DF_OUTPUT" | awk '{print $1}')
  USED_GB=$(echo "$DF_OUTPUT" | awk '{print $2}')
  USAGE=$(echo "$DF_OUTPUT" | awk '{print $3}')

  if [ "$USAGE" -ge 90 ]; then
    TITLE="Disk Status: $NODE_NAME"
    BODY="node=$NODE_NAME
path=/
usage=${USAGE}%
total=${TOTAL_GB}GB
used=${USED_GB}GB"

    echo "$BODY" | curl \
      -sSf \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: $TITLE" \
      -d @- \
      "$NTFY_URL/$NTFY_TOPIC"
    echo "ALERT: disk usage ${USAGE}% (${USED_GB}GB / ${TOTAL_GB}GB)"
  else
    echo "disk usage ${USAGE}% (${USED_GB}GB / ${TOTAL_GB}GB) - below threshold"
  fi

  sleep 3600
done
