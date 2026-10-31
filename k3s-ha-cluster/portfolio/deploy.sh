#!/usr/bin/env bash
# Regenerate the committed ConfigMap manifests from the gitignored source dirs.
# Source of truth: html/index.html (page) and img/ (photographs). After running,
# commit the manifests — the Forgejo deploy-portfolio workflow ships them on push.
set -euo pipefail
cd "$(dirname "$0")"
kubectl create configmap portfolio-html -n portfolio \
  --from-file=index.html=html/index.html \
  --dry-run=client -o yaml > configmap.yaml
kubectl create configmap portfolio-assets -n portfolio \
  --from-file=img/ \
  --dry-run=client -o yaml > assets-configmap.yaml
for f in configmap.yaml assets-configmap.yaml; do
  b=$(wc -c < "$f")
  # ConfigMap hard cap is 1 MiB; fail loudly at 95%.
  [ "$b" -lt 1000000 ] || { echo "$f is ${b}B — over the ConfigMap budget"; exit 1; }
done
echo "regenerated: $(wc -c < configmap.yaml)B page, $(wc -c < assets-configmap.yaml)B assets"
