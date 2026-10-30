# Homelab topology

On-demand topology snapshot for `yukselcloud.com`. Verify changing details
against `terraform/`, `k3s-ha-cluster/`, and the live cluster before editing.

## Nodes

| Node            | IP             | Role          | Host or storage |
| --------------- | -------------- | ------------- | --------------- |
| `infra-pi`      | 192.168.0.10   | Control plane | Bare metal, SD  |
| `k8s-node-171`  | 192.168.0.171  | Control plane | `lab-pve1`      |
| `k8s-node-172`  | 192.168.0.172  | Worker        | `lab-pve1`      |
| `k8s-node-181`  | 192.168.0.181  | Control plane | `lab-pve2`      |
| `k8s-node-182`  | 192.168.0.182  | Worker        | `lab-pve2`      |

- The three control planes form the HA quorum; 172 and 182 are workers.
- The Pi is ARM64, manually provisioned, and excluded from Longhorn.
- Caddy uses the `master-ingress` nodes. Verify current labels and selectors
  before changing scheduling.

## Proxmox placement

| Setting                 | Convention                       |
| ----------------------- | -------------------------------- |
| PVE cluster             | `lab-pve1` and `lab-pve2`        |
| LAN                     | `192.168.0.0/24`, `vmbr0`        |
| Control-plane VM disks  | `local-lvm`                      |
| Worker VM disks         | `shared-nfs`                     |
| Cloud-init and ISOs     | Directory datastore, usually `local` |
| Template on `lab-pve1`  | VM 9000                          |
| Template on `lab-pve2`  | VM 9001                          |

VM IDs traditionally match the final IP octet. Confirm this and all template
IDs in current tfvars before provisioning.

## Core cluster choices

- K3s API HA uses kube-vip; the K3s datastore is external MariaDB.
- Caddy provides ingress, MetalLB provides LoadBalancer addresses, and
  Longhorn provides replicated storage on the four VMs.
- Authelia, LLDAP, and Redis provide authentication. CrowdSec integrates
  with Caddy for edge enforcement.
- Forgejo is the primary Git server and Actions runner platform.

For current service namespaces, IPs, and deployment methods, inspect the
repository instead of maintaining a second inventory in this reference.
