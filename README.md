# Maestro homelab

## 🏡 High-Availability K3s Cluster for Homelab

Featuring kube-vip for HA control-plane, MetalLB for LoadBalancer services,
Pi-hole for DNS/ad-blocking, and Caddy as Ingress controller. Built on bare
metal with mixed ARM/AMD nodes.

## 🖥️ Physical Lab Inventory

A concise overview of the hardware powering this homelab:

- 💻 **GMTec Mini PC**
  Intel N150, 16GB DDR4 RAM, 256GB NVMe SSD

- 💻 **Beelink S13 Mini PC**
  Intel N150, 16GB DDR4 RAM, 500GB M.2 SSD

- 🍓 **Raspberry Pi 4B**
  8GB RAM, 256GB microSD card

- 📶 **TP-Link AX150**
  Gigabit WiFi 6 Router

- 🔌 **TP-Link 5-Port Gigabit Switch**

This blend of x86 and ARM hardware, combined with robust networking, provides a
flexible and resilient foundation for experimentation and learning.

## 🧱 Infrastructure with Proxmox + Terraform

We use Proxmox VE to manage bare-metal virtualization and Terraform to automate
VM provisioning:

    🖥️ VMs are provisioned on multiple nodes using Proxmox's API.

    📦 Each VM is bootstrapped with cloud-init templates.

    ⚙️ Terraform handles:

        VM creation

        Resource allocation (CPU, memory, disk)

        SSH key injection

        Network config

**Directory:** [terraform](/terraform/)

## ☸️ High-Availability K3s Cluster

Our HA K3s setup is designed for simplicity and resilience:

    🛢️ External MariaDB runs on the Proxmox host to serve as the K3s datastore.

    🧠 kube-vip provides a virtual IP (VIP) for accessing the K3s API across masters.

    🌐 MetalLB manages service-level LoadBalancer IPs for internal services.

    🌍 Caddy Ingress handles domain-based routing for services.

    🧅 Pi-hole runs in-cluster to serve local DNS + ad blocking, accessible at pihole.lab.local.

**Directory:** [k3s-ha-cluster](/k3s-ha-cluster/)

---

## 🔗 Inspiration & References

This project draws inspiration and practical ideas from the following excellent
resources. Many thanks to their authors for sharing their knowledge with the
community:

- [Kubernetes Homelab Overview by Jonathan Gazeley](https://jonathangazeley.com/2023/01/15/kubernetes-homelab-part-1-overview/)
- [TheTaqiTahmid/homeserver GitHub Repository](https://github.com/TheTaqiTahmid/homeserver)

## TODOS

- Develop a way to uncordon/cordon a node in the clsuter, drain it, delete the VM,
create vm via terraform without manually commenting uncommenting stuff, setup ssh
access, install k3s back.
