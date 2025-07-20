#!/bin/bash
set -euo pipefail

# Generate SSH key if it doesn't exist
if [[ ! -f ~/.ssh/id_rsa ]]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# master node IPs
masters=("192.168.0.171" "192.168.0.181" "192.168.0.10")

for ip in "${masters[@]}"; do
    echo ">>> Setting up SSH access for $ip"
    # Copy SSH key to remote host, -o StrictHostKeyChecking=no to automatically add host to known_hosts
    ssh-copy-id -o StrictHostKeyChecking=no lab@$ip
done

echo ">>> SSH setup complete. You can now run install scripts without password prompts."
