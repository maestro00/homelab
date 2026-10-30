---
name: homelab-terraform
description: >
  Use when working on Tay's Proxmox or Terraform infrastructure: PVE VMs,
  LXC containers, Paperclip provisioning, cloud-init, bridges, VLANs,
  datastores, bpg/proxmox, or K3s node provisioning. Do not use for
  Kubernetes workload deployment; use homelab-k3s instead.
---

# Homelab Terraform

Make answers topology-aware and consistent with the repository. Tay is
learning Proxmox, so explain new concepts before showing configuration.

## Durable rules

- Treat `terraform/`, `lxc/`, and their READMEs as canonical; inspect them
  before editing. This skill is a router, not an infrastructure inventory.
- Keep the Pi outside Terraform automation and retain an odd number of K3s
  control planes.
- Preserve existing variable, `for_each`, naming, and secret-handling
  patterns rather than introducing a parallel style.

## Load only what the task needs

- Terraform style and change workflow:
  [conventions](references/terraform-conventions.md).
- New Proxmox resource schemas:
  [bpg/proxmox resources](references/bpg-proxmox-resources.md).
- Node placement, templates, datastores, or cluster topology:
  [shared topology](../shared/topology.md).
- Router, DNS, or Tailscale details:
  [network reference](../homelab-k3s/references/router-and-tailscale.md).

## Change workflow

1. Inspect existing resources, variables, tfvars, and relevant LXC files.
2. Load only the references required by the task.
3. Explain the concept, show the resource and matching tfvars, then identify
   dependencies and any manual Proxmox steps.
4. Format and validate Terraform; review a plan before applying changes.
