# Maestro homelab

## 🏡 High-Availability K3s Cluster for Homelab

Featuring kube-vip for HA control-plane, MetalLB for LoadBalancer services,
Pi-hole for DNS/ad-blocking, and Caddy as Ingress controller. Built on bare
metal with mixed ARM/AMD nodes.

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
