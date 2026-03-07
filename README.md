# Maestro homelab

## 🏡 High-Availability K3s Cluster for Homelab

This is a bookkeeping for setup of my infrastucture and services.
It features kube-vip for HA control-plane, MetalLB for LoadBalancer services,
Pi-hole for DNS/ad-blocking along with unbound, and Caddy for reverse proxy
and etc.

## 🖥️ Physical Lab Inventory

A concise overview of the hardware powering this homelab:

- 💻 **GMTec Mini PC**
  Intel N150, 16GB DDR4 RAM, 256GB NVMe SSD

- 💻 **Beelink S13 Mini PC**
  Intel N150, 16GB DDR4 RAM, 500GB M.2 SSD

- 🍓 **Raspberry Pi 4B**
  8GB RAM, 256GB microSD card

- 📶 **GL.inet Flint 3e - OpenWRT**
  Wifi-7 Router, with 2.5gigabit ports

## 🧱 Infrastructure with Proxmox + Terraform

I use Proxmox VE to manage bare-metal virtualization and Terraform to automate
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

K3s HA setup is designed for simplicity, resilience, and a rich self-hosted ecosystem:

### 🏗️ Core Infrastructure & Storage

- 🛢️ **External MariaDB:** Runs on the Proxmox host to serve as K3s datastore.
- 🧠 **kube-vip:** Provides a virtual IP (VIP) for easy access to the K3s API.
- 💾 **Longhorn:** Distributed block storage providing persistent,
replicated volumes across the cluster.

### 🌐 Networking & Security

- 🧲 **MetalLB:** Manages service-level LoadBalancer IPs for internal cluster services.
- 🌍 **Caddy Ingress:** Handles clean, domain-based routing and automatic SSL
for all web services.
- 👮 **CrowdSec:** Integrates directly with Caddy to detect and block known
malicious IPs and brute-force attacks.
- 🧅 **Pi-hole + Unbound:** Runs bare metal rpi4 to serve fast local DNS resolution
and network-wide ad blocking.
- 🔄 **Cloudflare DDNS:** Automatically updates my public Cloudflare DNS entries
by cron run.
- 🔒 **Tailscale VPN:** Deployed on a bare-metal Raspberry Pi 4 node for secure,
zero-trust remote network access.

### 🛠️ DevOps & Management

- 🐙 **Forgejo Git Server:** Self-hosted Git repository complete with
local actions runners to automatically deploy configuration changes.
- 💻 **Termix:** Provides a web-based terminal for easy remote access to nodes
(accessible securely via Tailscale).

### 🏠 Media & Dashboards

- 📊 **Homer:** A clean, static dashboard for quick access to all homelab services.
- 🍿 **Media Stack:** The full *Arr* suite paired with Jellyfin for internal
media management and streaming.

**Directory:** [`/k3s-ha-cluster/`](/k3s-ha-cluster/)

---

## 🔗 Inspiration & References

This project draws inspiration and practical ideas from the following excellent
resources. Many thanks to their authors for sharing their knowledge with the
community:

- [Kubernetes Homelab Overview by Jonathan Gazeley](https://jonathangazeley.com/2023/01/15/kubernetes-homelab-part-1-overview/)
- [TheTaqiTahmid/homeserver GitHub Repository](https://github.com/TheTaqiTahmid/homeserver)
