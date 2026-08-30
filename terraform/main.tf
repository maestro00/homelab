terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.38"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = true
}

variable "nodes" {
  type = list(object({
    vm_name              = string
    vm_id                = number
    vm_ipv4_address      = string
    vm_target_node       = string
    vm_template_vm_id    = number
    cpu_cores            = number
    cpu_sockets          = number
    memory_dedicated     = number
    disk_size            = number
    storage_datastore_id = string
  }))
}

variable "containers" {
  type = list(object({
    name                 = string
    ct_id                = number
    hostname             = string
    ipv4_address         = string
    target_node          = string
    cpu_cores            = number
    memory_mb            = number
    disk_size            = number
    storage_datastore_id = string
    description          = optional(string, "")
  }))
  description = "LXC containers on the Proxmox hosts (e.g. the always-on opencode server)"
  default     = []
}

resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each = { for node in var.nodes : node.vm_name => node }

  name      = each.value.vm_name
  vm_id     = each.value.vm_id
  node_name = each.value.vm_target_node

  clone {
    vm_id = each.value.vm_template_vm_id
  }

  cpu {
    cores   = each.value.cpu_cores   # 2
    sockets = each.value.cpu_sockets # 1
  }

  memory {
    dedicated = each.value.memory_dedicated # 7680 # 7.5 GB
  }

  disk {
    datastore_id = each.value.storage_datastore_id # "local-lvm" or "shared-nfs"
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.vm_ipv4_address
        gateway = var.vm_ipv4_gateway
      }
    }

    user_account {
      username = "lab"
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each     = { for node in var.nodes : node.vm_name => node }
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.vm_target_node

  source_raw {
    data      = templatefile("${path.module}/cloud-init/kubernetes-node.yaml", { hostname = each.value.vm_name, lab_password_hash = var.lab_password_hash })
    file_name = "cloud-init-${each.value.vm_name}.yaml"
  }
}

# --- LXC containers (lightweight services sharing the host kernel) ---
resource "proxmox_virtual_environment_file" "lxc_template" {
  for_each     = { for ct in var.containers : ct.name => ct }
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = each.value.target_node

  source_file {
    path      = "http://download.proxmox.com/images/system/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    file_name = "ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  }
}

resource "proxmox_virtual_environment_container" "lxc" {
  for_each = { for ct in var.containers : ct.name => ct }

  node_name   = each.value.target_node
  vm_id       = each.value.ct_id
  description = each.value.description

  operating_system {
    template_file_id = proxmox_virtual_environment_file.lxc_template[each.key].id
    type             = "ubuntu"
  }

  initialization {
    hostname = each.value.hostname

    # Static IP on the main LAN (same vmbr0 as the VMs)
    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = var.vm_ipv4_gateway
      }
    }

    # Root SSH access with the workstation key (bootstrap script connects here)
    user_account {
      keys = [trimspace(file(var.container_ssh_public_key))]
    }
  }

  cpu {
    cores = each.value.cpu_cores # LXC shares host CPU; this is a limit
  }

  memory {
    dedicated = each.value.memory_mb
    swap      = 0
  }

  disk {
    datastore_id = each.value.storage_datastore_id
    size         = each.value.disk_size
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr0"
    enabled = true
  }

  # tun needed by tailscaled inside the container (/dev/net/tun).
  # PVE feature list has no `tun` flag on this version -> device passthrough.
  device_passthrough {
    path = "/dev/net/tun"
    mode = "0777"
  }

  unprivileged  = true
  start_on_boot = true
  started       = true
}
