proxmox_url      = "https://192.168.0.51:8006/api2/json"
proxmox_user     = "root@pam"
proxmox_password = "password"
target_node      = "lab-pve1"
vm_ipv4_gateway  = "192.168.0.1"
nodes = [
  {
    vm_name           = "k8s-node-171"
    vm_id             = 171
    vm_ipv4_address   = "192.168.0.171/24"
    vm_target_node    = "lab-pve1"
    vm_template_vm_id = 9000
  },
  {
    vm_name           = "k8s-node-172"
    vm_id             = 172
    vm_ipv4_address   = "192.168.0.172/24"
    vm_target_node    = "lab-pve1"
    vm_template_vm_id = 9000
  },
  {
    vm_name           = "k8s-node-181"
    vm_id             = 181
    vm_ipv4_address   = "192.168.0.181/24"
    vm_target_node    = "lab-pve2"
    vm_template_vm_id = 9001
  },
  {
    vm_name           = "k8s-node-182"
    vm_id             = 182
    vm_ipv4_address   = "192.168.0.182/24"
    vm_target_node    = "lab-pve2"
    vm_template_vm_id = 9001
  }
]
