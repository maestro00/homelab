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

variable "lab_password_hash" {
  type        = string
  description = "SHA-512 password hash for the 'lab' user in cloud-init."
  sensitive   = true
  default     = "$6$placeholder$PLACEHOLDER_REPLACE_VIA_GITIGNORED_OVERRIDE"
}
