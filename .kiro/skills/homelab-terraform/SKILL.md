---
name: homelab-terraform
description: >
  Expert guide for Tay's yukselcloud.com homelab Terraform infrastructure. Use this skill
  whenever Tay asks about: provisioning VMs on Proxmox, extending Terraform configs,
  adding new resource types (LXC, network bridges, VLANs, storage pools), K3s node
  management, cloud-init, the bpg/proxmox provider API, or anything related to the
  homelab setup. Also trigger for general Terraform questions — apply Tay's existing
  code style and conventions in all answers. If the question mentions proxmox, k3s,
  homelab, terraform, pve, vmbr, or any node name (k8s-node-171/172/181/182, pi), use
  this skill immediately.
---

# Homelab Terraform Skill

This skill gives Claude full context of Tay's homelab so answers are always topology-aware,
code-style-consistent, and educational (Tay is actively learning Proxmox).

---

## Topology Reference

### Physical Machines

| Host | Type | Role | Proxmox Node |
|------|------|------|--------------|
| Mini PC 1 (Intel N150) | Physical | Proxmox hypervisor | `lab-pve1` |
| Mini PC 2 (Intel N150) | Physical | Proxmox hypervisor | `lab-pve2` |
| Raspberry Pi 4B | Physical (bare metal) | K3s control plane | n/a (no Proxmox) |

- `lab-pve1` and `lab-pve2` run **clustered Proxmox VE**
- Pi was provisioned manually via Raspberry Pi Imager (SD card), not Terraform

### Network

- LAN subnet: `192.168.0.0/24`
- Gateway: `192.168.0.1` (GL.iNet Flint 3E, OpenWrt)
- Domain: `yukselcloud.com` (external + internal via split DNS / Caddy)
- Current bridges: only `vmbr0` (main LAN) on both PVE hosts
- VLANs: none yet — planned future work

### K3s HA Cluster (5 nodes)

| Node | VM ID | IP | PVE Host | K3s Role | Storage |
|------|-------|----|----------|----------|---------|
| k8s-node-171 | 171 | 192.168.0.171 | lab-pve1 | Control plane | local-lvm |
| k8s-node-172 | 172 | 192.168.0.172 | lab-pve1 | Worker | shared-nfs |
| k8s-node-181 | 181 | 192.168.0.181 | lab-pve2 | Control plane | local-lvm |
| k8s-node-182 | 182 | 192.168.0.182 | lab-pve2 | Worker | shared-nfs |
| Raspberry Pi 4B | n/a | 192.168.0.10 | bare metal | Control plane | SD card |

**Control planes**: 171, 181, Pi (3 nodes — proper HA quorum)
**Workers**: 172, 182

### Storage Datastores (per PVE host)

| Datastore | Type | Used for |
|-----------|------|----------|
| `local-lvm` | LVM thin | Control plane VMs (fast local disk) |
| `shared-nfs` | NFS share | Worker VMs (shared across both PVE hosts) |
| `local` | Directory | Cloud-init snippets, ISO images |

### VM Templates

| Template VM ID | PVE Host | Base OS |
|----------------|----------|---------|
| 9000 | lab-pve1 | Ubuntu (cloud image) |
| 9001 | lab-pve2 | Ubuntu (cloud image) |

---

## Code Conventions

Always follow these patterns when generating or modifying Terraform for this homelab.

### Provider

```hcl
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
  insecure = true  # self-signed cert on PVE
}
```

### File Layout

```
terraform/
├── main.tf           # provider + resources
├── variables.tf      # variable declarations with descriptions
├── node.tfvars       # actual values (gitignored for secrets)
└── cloud-init/
    └── <template>.yaml
```

### Variable Style

- Declare all variables in `variables.tf` with `type`, `description`, and `default` where sensible
- Pass actual values via `.tfvars` files, never hardcode in `main.tf`
- Sensitive values (`password`, tokens) get `sensitive = true`
- Use `list(object({...}))` for repeating resources (VMs, containers, etc.)

### Resource Pattern: `for_each` over a list

Always convert `list(object)` vars to a map using `for_each`:

```hcl
for_each = { for item in var.items : item.name => item }
```

Then reference with `each.value.<field>`.

### Cloud-init

- Template file lives in `cloud-init/<name>.yaml`
- Rendered with `templatefile()` and uploaded as a snippet to the `local` datastore
- Always includes: `hostname`, `lab` user, passwordless sudo, common packages
- `resolvconf` and `nfs-common` are standard includes for K3s nodes

### Naming Conventions

- VMs: `k8s-node-<last-octet>` (e.g. `k8s-node-171`)
- VM IDs: match last octet of IP (e.g. IP `.171` → VM ID `171`)
- Variables: `snake_case`
- Resources: `snake_case`, descriptive (e.g. `proxmox_virtual_environment_vm.k8s_node`)

---

## bpg/proxmox Provider Reference

Read `references/bpg-proxmox-resources.md` for detailed resource schemas.
Key resources covered there:
- `proxmox_virtual_environment_vm` — VMs (already in use)
- `proxmox_virtual_environment_container` — LXC containers
- `proxmox_virtual_environment_network_linux_bridge` — Linux bridges (vmbr*)
- `proxmox_virtual_environment_file` — uploading cloud-init snippets, ISOs
- `proxmox_virtual_environment_pool` — resource pools

---

## Teaching Mode

Tay is actively learning Proxmox. When introducing a new resource type or concept:

1. **Explain the concept first** — what is it, why use it, how Proxmox models it
2. **Show the Terraform resource** — with all fields annotated via comments
3. **Show the matching tfvars block** — following the list(object) pattern
4. **Explain the relationship** to existing resources (e.g. a bridge referenced by a VM's `network_device`)
5. **Note any manual Proxmox UI steps** that Terraform can't fully automate (e.g. VLAN-aware bridge requires a PVE host network config change)

---

## Workflow: Adding a New VM

When Tay wants to add a new K3s node, scaffold all of these:

1. New entry in `node.tfvars` `nodes` list — follow IP→ID convention, assign correct `vm_target_node` and `storage_datastore_id` based on topology
2. Confirm whether it's a control plane (→ `local-lvm`) or worker (→ `shared-nfs`)
3. Reference the correct template VM ID for the target PVE host (9000 for pve1, 9001 for pve2)
4. No changes needed to `main.tf` or `variables.tf` — the `for_each` handles it

---

## Workflow: Adding a New Resource Type

1. Read the relevant section in `references/bpg-proxmox-resources.md`
2. Explain the concept (Teaching Mode above)
3. Create a new `resource "proxmox_virtual_environment_<type>" "<name>"` block in `main.tf`
4. Add corresponding variable declarations to `variables.tf`
5. Add example values to `node.tfvars`
6. Note any dependencies (e.g. a VLAN bridge must exist before a VM can use it)

---

## Common Gotchas

- **`insecure = true`** is required — PVE uses a self-signed TLS cert
- **Cloud-init snippets** must go to the `local` datastore (directory type), not `local-lvm`
- **`shared-nfs`** must be mounted on both PVE hosts before Terraform runs
- **VM template IDs differ per host** — 9000 on pve1, 9001 on pve2; always check `vm_target_node`
- **K3s HA requires odd number of control planes** — currently 3 (171, 181, Pi) ✓
- **Pi is not managed by Terraform** — manual node, treat as static in any automation
