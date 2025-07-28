#!/bin/bash
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly SSH_USER="lab"
readonly SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
readonly K3S_INSTALL_URL="https://get.k3s.io"

# Node configuration
declare -A NODES=(
    ["192.168.0.171"]="master"
    ["192.168.0.181"]="master"
    ["192.168.0.10"]="master"
    ["192.168.0.172"]="worker"
    ["192.168.0.182"]="worker"
)

readonly CLUSTER_VIP="192.168.0.100"
readonly DB_HOST="192.168.0.52"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Validation functions
validate_environment() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Missing .env file at $ENV_FILE"
        exit 1
    fi

    source "$ENV_FILE"

    if [[ -z "${K3S_TOKEN:-}" ]]; then
        log_error "K3S_TOKEN not set in .env file"
        exit 1
    fi

    if [[ -z "${K3S_DB_PASSWORD:-}" ]]; then
        log_error "K3S_DB_PASSWORD not set in .env file"
        exit 1
    fi

    log_success "Environment validation passed"
}

validate_connectivity() {
    local failed_nodes=()

    for node in "${!NODES[@]}"; do
        if ! ssh $SSH_OPTS "$SSH_USER@$node" "echo 'Connection test'" >/dev/null 2>&1; then
            failed_nodes+=("$node")
        fi
    done

    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        log_error "Cannot connect to nodes: ${failed_nodes[*]}"
        exit 1
    fi

    log_success "Connectivity validation passed"
}

# Utility functions
execute_remote() {
    local node="$1"
    local command="$2"
    local description="${3:-Executing command on $node}"

    log_info "$description"
    if ! ssh $SSH_OPTS "$SSH_USER@$node" "$command"; then
        log_error "Failed to execute command on $node: $command"
        return 1
    fi
}

wait_with_feedback() {
    local seconds="$1"
    local message="${2:-Waiting}"

    log_info "$message for $seconds seconds..."
    sleep "$seconds"
}

# K3s installation functions
prepare_node_environment() {
    local node="$1"
    local node_type="$2"

    log_info "Preparing environment on $node ($node_type)"

    local env_content
    if [[ "$node_type" == "master" ]]; then
        env_content="K3S_TOKEN=${K3S_TOKEN}\\nK3S_DATASTORE_ENDPOINT=mysql://k3suser:${K3S_DB_PASSWORD}@tcp(${DB_HOST}:3306)/k3s"
        local env_file="/etc/k3s/cluster.env"
    else
        env_content="K3S_TOKEN=${K3S_TOKEN}\\nK3S_URL=https://${CLUSTER_VIP}:6443"
        local env_file="/etc/k3s/worker.env"
    fi

    execute_remote "$node" "
        sudo mkdir -p /etc/k3s &&
        echo -e \"$env_content\" | sudo tee $env_file > /dev/null
    " "Setting up environment file on $node"
}

install_k3s_master() {
    local node="$1"
    local is_first_master="$2"

    log_info "Installing K3s server on $node (first master: $is_first_master)"

    local cluster_init_flag=""
    if [[ "$is_first_master" == "true" ]]; then
        cluster_init_flag="--cluster-init"
        log_info "This is the first master node - initializing cluster"
    fi

    execute_remote "$node" "
        sudo INSTALL_K3S_SKIP_START=true sh -c '
            curl -sfL $K3S_INSTALL_URL | sh -s - server \\
                $cluster_init_flag \\
                --disable=traefik \\
                --tls-san=$CLUSTER_VIP \\
                --datastore-endpoint=\$(grep ^K3S_DATASTORE_ENDPOINT /etc/k3s/cluster.env | cut -d= -f2-) \\
                --token=\$(grep ^K3S_TOKEN /etc/k3s/cluster.env | cut -d= -f2-)
        '
    " "Installing K3s server on $node"
}

install_k3s_worker() {
    local node="$1"

    log_info "Installing K3s agent on $node"

    execute_remote "$node" "
        sudo INSTALL_K3S_SKIP_START=true sh -c '
            curl -sfL $K3S_INSTALL_URL | \\
            K3S_URL=https://$CLUSTER_VIP:6443 \\
            K3S_TOKEN=$K3S_TOKEN \\
            sh -s - agent
        '
    " "Installing K3s agent on $node"
}

start_k3s_service() {
    local node="$1"
    local node_type="$2"

    local service_name="k3s"
    if [[ "$node_type" == "worker" ]]; then
        service_name="k3s-agent"
    fi

    execute_remote "$node" "sudo systemctl start $service_name" "Starting $service_name on $node"
    log_success "K3s service started on $node"
}

# Main installation workflow
install_masters() {
    local master_nodes=()

    # Collect master nodes
    for node in "${!NODES[@]}"; do
        if [[ "${NODES[$node]}" == "master" ]]; then
            master_nodes+=("$node")
        fi
    done

    log_info "Found ${#master_nodes[@]} master nodes: ${master_nodes[*]}"

    # Install masters
    for i in "${!master_nodes[@]}"; do
        local node="${master_nodes[$i]}"
        local is_first_master="false"

        if [[ $i -eq 0 ]]; then
            is_first_master="true"
        fi

        prepare_node_environment "$node" "master"
        install_k3s_master "$node" "$is_first_master"
        wait_with_feedback 10 "Allowing K3s to initialize on $node"
        start_k3s_service "$node" "master"

        log_success "Master node $node installation completed"
    done
}

install_workers() {
    local worker_nodes=()

    # Collect worker nodes
    for node in "${!NODES[@]}"; do
        if [[ "${NODES[$node]}" == "worker" ]]; then
            worker_nodes+=("$node")
        fi
    done

    if [[ ${#worker_nodes[@]} -eq 0 ]]; then
        log_warning "No worker nodes found"
        return 0
    fi

    log_info "Found ${#worker_nodes[@]} worker nodes: ${worker_nodes[*]}"

    # Install workers
    for node in "${worker_nodes[@]}"; do
        prepare_node_environment "$node" "worker"
        install_k3s_worker "$node"
        wait_with_feedback 5 "Allowing K3s agent to initialize on $node"
        start_k3s_service "$node" "worker"

        log_success "Worker node $node installation completed"
    done
}

# Main execution
main() {
    log_info "Starting K3s cluster installation"

    validate_environment
    validate_connectivity

    log_info "Installing master nodes..."
    install_masters

    log_info "Installing worker nodes..."
    install_workers

    log_success "K3s cluster installation completed successfully!"
    log_info "Cluster VIP: $CLUSTER_VIP"
    log_info "You can now access your cluster using kubectl"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
