# bpg/proxmox Provider Resource Reference

Provider source: `bpg/proxmox`, version `~> 0.38`
Docs: <https://registry.terraform.io/providers/bpg/proxmox/latest/docs>

---

## Table of Contents

1. [proxmox_virtual_environment_vm](#vm) — already in use
2. [proxmox_virtual_environment_container](#lxc) — LXC containers
3. [proxmox_virtual_environment_network_linux_bridge](#bridge) — Linux bridges / VLANs
4. [proxmox_virtual_environment_file](#file) — cloud-init snippets, ISOs
5. [proxmox_virtual_environment_pool](#pool) — resource pools

---

## 1. proxmox_virtual_environment_vm {#vm}

Already in active use. Key fields recap:

```hcl
resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each  = { for node in var.nodes : node.vm_name => node }
  name      = each.value.vm_name
  vm_id     = each.value.vm_id
  node_name = each.value.vm_target_node   # "lab-pve1" or "lab-pve2"

  clone {
    vm_id = each.value.vm_template_vm_id  # 9000 (pve1) or 9001 (pve2)
  }

  cpu {
    cores   = each.value.cpu_cores
    sockets = each.value.cpu_sockets
  }

  memory {
    dedicated = each.value.memory_dedicated  # in MB
  }

  disk {
    datastore_id = each.value.storage_datastore_id
    interface    = "scsi0"
    size         = each.value.disk_size  # in GB
  }

  network_device {
    bridge = "vmbr0"  # Linux bridge name on PVE host
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.vm_ipv4_address  # e.g. "192.168.0.171/24"
        gateway = var.vm_ipv4_gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }
}
```

---

## 2. proxmox_virtual_environment_container {#lxc}

### Concept

LXC (Linux Containers) are lightweight OS-level virtualization — they share the host kernel
(unlike VMs which have their own). They boot in milliseconds, use far less RAM and disk, but
can only run Linux. Good for: simple services (DNS, monitoring agents, databases, app servers)
that don't need full VM isolation.

In Proxmox: VMs get IDs, LXC containers also get IDs. They appear side-by-side in the PVE UI.

### Terraform Resource

```hcl
resource "proxmox_virtual_environment_container" "lxc" {
  for_each  = { for ct in var.containers : ct.name => ct }

  node_name = each.value.target_node    # "lab-pve1" or "lab-pve2"
  vm_id     = each.value.ct_id          # integer, e.g. 200
  description = each.value.description  # optional, shows in PVE UI

  # The base OS template (downloaded to local datastore first)
  operating_system {
    template_file_id = each.value.template_file_id
    # e.g. "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    type             = "ubuntu"  # or "debian", "centos", etc.
  }

  initialization {
    hostname = each.value.hostname

    # Network config inside the container
    ip_config {
      ipv4 {
        address = each.value.ipv4_address  # e.g. "192.168.0.200/24"
        gateway = var.vm_ipv4_gateway
      }
    }

    # Root password or SSH key
    user_account {
      password = var.ct_root_password
      # keys = [file("~/.ssh/id_rsa.pub")]  # alternative: SSH key auth
    }
  }

  cpu {
    cores = each.value.cpu_cores  # LXC shares host CPU, so just a limit
  }

  memory {
    dedicated = each.value.memory_mb   # in MB
    swap      = each.value.swap_mb     # swap in MB, 0 to disable
  }

  disk {
    datastore_id = each.value.storage_datastore_id
    size         = each.value.disk_size  # in GB
  }

  network_interface {
    name   = "eth0"           # interface name inside the container
    bridge = "vmbr0"          # PVE host bridge
    enabled = true
  }

  # Recommended for most containers
  unprivileged = true   # more secure; some workloads need false (e.g. Docker-in-LXC)
  start_on_boot = true
  started       = true
}
```

### Variables (variables.tf)

```hcl
variable "containers" {
  type = list(object({
    name                 = string
    ct_id                = number
    hostname             = string
    target_node          = string
    template_file_id     = string
    ipv4_address         = string
    cpu_cores            = number
    memory_mb            = number
    swap_mb              = number
    disk_size            = number
    storage_datastore_id = string
    description          = optional(string, "")
  }))
}

variable "ct_root_password" {
  type      = string
  sensitive = true
}
```

### Example tfvars entry

```hcl
containers = [
  {
    name                 = "ct-pihole"
    ct_id                = 200
    hostname             = "pihole"
    target_node          = "lab-pve1"
    template_file_id     = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    ipv4_address         = "192.168.0.200/24"
    cpu_cores            = 1
    memory_mb            = 512
    swap_mb              = 0
    disk_size            = 8
    storage_datastore_id = "local-lvm"
    description          = "Pi-hole DNS sinkhole"
  }
]
```

### LXC vs VM — when to use which

| Use LXC when... | Use VM when... |
|-----------------|---------------|
| Simple Linux service (DNS, proxy, agent) | Need Windows or non-Linux OS |
| Fast spin-up, low overhead | Need kernel-level isolation |
| You trust the workload | Running Docker/K3s (needs VM) |
| Dev/test throwaway envs | Production stateful workloads |

---

## 3. proxmox_virtual_environment_network_linux_bridge {#bridge}

### Concept

A **Linux bridge** (vmbr*) is a virtual switch inside the PVE host. VMs and containers
attach their virtual NICs to a bridge, and the bridge connects them to the physical NIC
or to each other (for internal-only networks).

**VLAN-aware bridge**: A single bridge can carry multiple VLANs. Each VM/container gets
a VLAN tag, and traffic is segmented at the bridge level. You need one VLAN-aware bridge
to do this (typically `vmbr0` made VLAN-aware, or a dedicated `vmbr1`).

**Key concepts:**

- `vmbr0`: your existing bridge — untagged LAN (192.168.0.0/24)
- VLAN IDs: 1–4094; conventionally e.g. VLAN 10 = management, VLAN 20 = IoT, VLAN 30 = lab
- The GL.iNet router also needs to be configured to trunk VLANs if you want inter-VLAN routing

### Terraform Resource

```hcl
resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1" {
  for_each = { for b in var.bridges : b.name => b }

  node_name = each.value.node_name     # must create on each PVE host separately
  name      = each.value.name          # e.g. "vmbr1"
  comment   = each.value.comment       # shown in PVE UI

  vlan_aware = each.value.vlan_aware   # true to enable VLAN tagging on this bridge

  # Optional: assign an IP to the bridge itself (for host routing)
  address = each.value.address         # e.g. "192.168.10.1/24" — or omit if unrouted
}
```

### Variables (variables.tf)

```hcl
variable "bridges" {
  type = list(object({
    name       = string
    node_name  = string
    comment    = optional(string, "")
    vlan_aware = optional(bool, false)
    address    = optional(string, null)
  }))
  default = []
}
```

### Example tfvars — VLAN-aware bridge on both PVE hosts

```hcl
bridges = [
  {
    name       = "vmbr1"
    node_name  = "lab-pve1"
    comment    = "VLAN-aware internal bridge"
    vlan_aware = true
  },
  {
    name       = "vmbr1"
    node_name  = "lab-pve2"
    comment    = "VLAN-aware internal bridge"
    vlan_aware = true
  }
]
```

### Attaching a VM to a specific VLAN

In the VM's `network_device` block, add `vlan_id`:

```hcl
network_device {
  bridge  = "vmbr1"
  model   = "virtio"
  vlan_id = 20   # this VM goes on VLAN 20
}
```

### Important: Manual step required

Terraform can create the bridge resource, but making it **physically connected to the
host NIC** requires editing `/etc/network/interfaces` on each PVE node — or doing it
via the PVE UI under System → Network. Terraform sets the bridge config in the PVE
database, but network interface binding to physical NICs is an OS-level config.

After applying, verify in PVE UI: Datacenter → lab-pve1 → System → Network.

---

## 4. proxmox_virtual_environment_file {#file}

### Concept

Used to upload files to a PVE datastore — most commonly cloud-init snippets (as in
the existing config) or ISO images.

### Already in use (cloud-init snippet upload)

```hcl
resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each     = { for node in var.nodes : node.vm_name => node }
  content_type = "snippets"
  datastore_id = "local"          # must be a directory-type datastore
  node_name    = each.value.vm_target_node

  source_raw {
    data      = templatefile("${path.module}/cloud-init/kubernetes-node.yaml", {
      hostname = each.value.vm_name
    })
    file_name = "cloud-init-${each.value.vm_name}.yaml"
  }
}
```

### Uploading an ISO image

```hcl
resource "proxmox_virtual_environment_file" "ubuntu_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "lab-pve1"

  source_file {
    path      = "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
    file_name = "ubuntu-22.04.3-server.iso"
  }
}
```

### Uploading an LXC template

```hcl
resource "proxmox_virtual_environment_file" "ubuntu_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "lab-pve1"

  source_file {
    path      = "http://download.proxmox.com/images/system/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    file_name = "ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  }
}
```

---

## 5. proxmox_virtual_environment_pool {#pool}

### Concept

A **pool** is a logical grouping of VMs and containers in the PVE UI. Useful for
organizing by purpose (e.g. "k3s-cluster", "monitoring", "homelab-services").
No functional impact — purely organizational.

```hcl
resource "proxmox_virtual_environment_pool" "k3s" {
  pool_id = "k3s-cluster"
  comment = "K3s HA cluster nodes"
}
```

To assign a VM to a pool, add `pool_id` to the VM resource:

```hcl
resource "proxmox_virtual_environment_vm" "k8s_node" {
  # ...existing config...
  pool_id = proxmox_virtual_environment_pool.k3s.pool_id
}
```
