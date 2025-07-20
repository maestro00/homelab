#!/bin/bash

#
# This script installs kube-vip on multiple K3s master nodes in a
# high-availability setup
# Run this script from your local machine defining your master nodes
#

set -euo pipefail

masters=("192.168.0.10")
username="lab"
vip="192.168.0.100"
interface="eth0"
kube_vip_version="v0.7.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if node is reachable
check_node() {
    local node=$1
    if ssh -o ConnectTimeout=5 -o BatchMode=yes ${username}@${node} "echo 'OK'" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get network interface (auto-detect)
get_interface() {
    local node=$1
    local interface_cmd="ip route | grep default | awk '{print \$5}' | head -1"
    ssh ${username}@${node} "${interface_cmd}" 2>/dev/null || echo "eth0"
}

# Function to install kube-vip on a single node
install_kube_vip_on_node() {
    local node=$1
    local node_interface=$(get_interface $node)

    print_status "Installing kube-vip on $node (interface: $node_interface)"

    # Create the kube-vip manifest
    ssh ${username}@${node} << EOF
# Create kube-vip directory if it doesn't exist
sudo mkdir -p /var/lib/rancher/k3s/server/manifests

# Create the kube-vip static pod manifest
sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml > /dev/null << 'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "${node_interface}"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_ddns
      value: "false"
    - name: svc_enable
      value: "true"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "${vip}"
    image: ghcr.io/kube-vip/kube-vip:${kube_vip_version}
    imagePullPolicy: Always
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        - SYS_TIME
    volumeMounts: []
  hostNetwork: true
status: {}
MANIFEST

echo "✓ Kube-VIP manifest created on $node"
EOF
}

# Function to update K3s configuration with VIP
update_k3s_config() {
    local node=$1

    print_status "Updating K3s configuration on $node to include VIP"

    ssh ${username}@${node} << EOF
# Check if config file exists
if [ ! -f /etc/rancher/k3s/config.yaml ]; then
    sudo mkdir -p /etc/rancher/k3s
    sudo touch /etc/rancher/k3s/config.yaml
fi

# Add tls-san for VIP if not already present
if ! sudo grep -q "tls-san:" /etc/rancher/k3s/config.yaml; then
    echo "tls-san:" | sudo tee -a /etc/rancher/k3s/config.yaml > /dev/null
fi

if ! sudo grep -q "  - ${vip}" /etc/rancher/k3s/config.yaml; then
    echo "  - ${vip}" | sudo tee -a /etc/rancher/k3s/config.yaml > /dev/null
fi

echo "✓ K3s config updated on $node"
EOF
}

# Function to restart K3s service
restart_k3s() {
    local node=$1

    print_status "Restarting K3s service on $node"

    ssh ${username}@${node} << EOF
sudo systemctl restart k3s
sleep 10
sudo systemctl status k3s --no-pager -l
EOF
}

# Main installation process
main() {
    print_status "Starting kube-vip installation on ${#masters[@]} master nodes"
    print_status "VIP: $vip"
    print_status "Masters: ${masters[*]}"

    # Check connectivity to all nodes
    print_status "Checking connectivity to all nodes..."
    for master in "${masters[@]}"; do
        if check_node "$master"; then
            print_status "✓ Node $master is reachable"
        else
            print_error "✗ Node $master is not reachable"
            exit 1
        fi
    done

    # Install kube-vip on all nodes
    for master in "${masters[@]}"; do
        echo ""
        print_status "Processing master node: $master"

        # Install kube-vip
        install_kube_vip_on_node "$master"

        # Update K3s config
        update_k3s_config "$master"

        print_status "✓ Kube-VIP installation completed on $master"
    done

    # Restart K3s services (do this after all manifests are created)
    print_status ""
    print_status "Restarting K3s services on all nodes..."
    for master in "${masters[@]}"; do
        restart_k3s "$master"
    done

    print_status ""
    print_status "Installation completed! Testing VIP..."

    # Test VIP
    sleep 15
    if ping -c 3 "$vip" &>/dev/null; then
        print_status "✓ VIP $vip is responding to ping"
    else
        print_warning "⚠ VIP $vip is not responding to ping yet (may take a few minutes)"
    fi

    # Test kubectl access
    print_status ""
    print_status "Testing kubectl access via VIP..."
    print_status "Update your kubeconfig to use the VIP:"
    print_status "kubectl config set-cluster default --server=https://$vip:6443"

    print_status ""
    print_status "🎉 Kube-VIP installation complete!"
    print_status "VIP: $vip"
    print_status "You can now access your cluster via: https://$vip:6443"
}

# Run main function
main "$@"
