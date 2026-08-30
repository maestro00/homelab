proxmox_url      = "https://192.168.0.51:8006/api2/json"
proxmox_user     = "root@pam"
proxmox_password = "PASSWORD_LOADED_FROM_GITIGNORED_OVERRIDE"
vm_ipv4_gateway  = "192.168.0.1"
nodes = [
  {
    vm_name              = "k8s-node-171"
    vm_id                = 171
    vm_ipv4_address      = "192.168.0.171/24"
    vm_target_node       = "lab-pve1"
    vm_template_vm_id    = 9000
    cpu_cores            = 2
    cpu_sockets          = 1
    memory_dedicated     = 6144
    disk_size            = 40
    storage_datastore_id = "local-lvm"
  },
  {
    vm_name              = "k8s-node-172"
    vm_id                = 172
    vm_ipv4_address      = "192.168.0.172/24"
    vm_target_node       = "lab-pve1"
    vm_template_vm_id    = 9000
    cpu_cores            = 2
    cpu_sockets          = 1
    memory_dedicated     = 6144
    disk_size            = 40
    storage_datastore_id = "shared-nfs"
  },
  {
    vm_name              = "k8s-node-181"
    vm_id                = 181
    vm_ipv4_address      = "192.168.0.181/24"
    vm_target_node       = "lab-pve2"
    vm_template_vm_id    = 9001
    cpu_cores            = 2
    cpu_sockets          = 1
    memory_dedicated     = 6144
    disk_size            = 40
    storage_datastore_id = "local-lvm"
  },
  {
    vm_name              = "k8s-node-182"
    vm_id                = 182
    vm_ipv4_address      = "192.168.0.182/24"
    vm_target_node       = "lab-pve2"
    vm_template_vm_id    = 9001
    cpu_cores            = 2
    cpu_sockets          = 1
    memory_dedicated     = 6144
    disk_size            = 40
    storage_datastore_id = "shared-nfs"
  }
]

containers = [
  {
    name                 = "opencode"
    ct_id                = 253
    hostname             = "opencode"
    ipv4_address         = "192.168.0.53/24"
    target_node          = "lab-pve2"
    cpu_cores            = 2
    # 1 GiB was too tight: opencode (Bun) + tailscaled + systemd hit 99% and
    # the container thrashed (sshd banner timeout, web UI hang)
    memory_mb            = 2048
    disk_size            = 16
    storage_datastore_id = "local-lvm"
    description          = "Always-on opencode server (Tailscale-only, no reverse proxy)"
  }
]
