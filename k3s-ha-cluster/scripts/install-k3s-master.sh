#!/bin/bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Missing .env file. Aborting."
  exit 1
fi

source .env

# Master node IPs (first one will do --cluster-init)
masters=("192.168.0.171" "192.168.0.181" "192.168.0.10")

K3S_DB_ENDPOINT="mysql://k3suser:$K3S_DB_PASSWORD@tcp(192.168.0.52:3306)/k3s"

for i in "${!masters[@]}"; do
  ip="${masters[$i]}"
  echo ">>> Installing on $ip"

  ssh -o StrictHostKeyChecking=no lab@$ip "sudo mkdir -p /etc/k3s && echo -e \"K3S_TOKEN=$K3S_TOKEN\nK3S_DATASTORE_ENDPOINT=$K3S_DB_ENDPOINT\" | sudo tee /etc/k3s/cluster.env > /dev/null"

  if [[ "$i" == 0 ]]; then
    # First node gets --cluster-init
    ssh -o StrictHostKeyChecking=no lab@$ip "sudo INSTALL_K3S_SKIP_START=true sh -c 'curl -sfL https://get.k3s.io | sh -s - server \
      --cluster-init \
      --disable=traefik \
      --tls-san=192.168.0.100 \
      --datastore-endpoint=\$(grep ^K3S_DATASTORE_ENDPOINT /etc/k3s/cluster.env | cut -d= -f2-) \
      --token=\$(grep ^K3S_TOKEN /etc/k3s/cluster.env | cut -d= -f2-)'"
  else
    ssh -o StrictHostKeyChecking=no lab@$ip "sudo INSTALL_K3S_SKIP_START=true sh -c 'curl -sfL https://get.k3s.io | sh -s - server \
      --disable=traefik \
      --tls-san=192.168.0.100 \
      --datastore-endpoint=\$(grep ^K3S_DATASTORE_ENDPOINT /etc/k3s/cluster.env | cut -d= -f2-) \
      --token=\$(grep ^K3S_TOKEN /etc/k3s/cluster.env | cut -d= -f2-)'"
  fi

  sleep 10
  echo ">>> Sleeped for 10 seconds to allow K3s to initialize on $ip"
  ssh -o StrictHostKeyChecking=no lab@$ip "sudo systemctl start k3s"
  echo ">>> Done with $ip"
done
