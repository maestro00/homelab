variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_user" {
  type = string
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "vm_ipv4_gateway" {
  type        = string
  description = "IPv4 gateway for the VM, e.g., 192.168.0.1"
  default     = "192.168.0.1"
}
