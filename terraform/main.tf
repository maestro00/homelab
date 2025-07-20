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
    vm_name           = string
    vm_id             = number
    vm_ipv4_address   = string
    vm_target_node    = string
    vm_template_vm_id = number
  }))
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
    cores   = 2
    sockets = 1
  }

  memory {
    dedicated = 7680 # 7.5 GB
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
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
    data      = templatefile("${path.module}/cloud-init/kubernetes-node.yaml", { hostname = each.value.vm_name })
    file_name = "cloud-init-${each.value.vm_name}.yaml"
  }
}
