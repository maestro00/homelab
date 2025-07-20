# ☁️ K3s HA Cluster with Pi-hole, Caddy, MetalLB & kube-vip

This project documents the setup of a lightweight, high-availability K3s cluster
running on bare metal with:

```text
  📡 kube-vip as a virtual IP for control-plane access

  🎛️ MetalLB for LoadBalancer services

  🌐 Caddy as Ingress Controller

  🚫 Pi-hole DNS server for ad-blocking and internal DNS
```

With this setup, we can host;

- Self-hosted GitOps tools (e.g. ArgoCD, Flux)
- Media servers (Plex, Jellyfin)
- Monitoring (Prometheus, Grafana)
- Web apps (Nextcloud, Ghost, etc.)
- Homelab dashboards, like Homer

## 🛠️ Infrastructure Overview

```text
  3x control-plane nodes: infra-pi, k8s-node-171, k8s-node-181
  (TODO: Worker nodes to be added)

  Architecture mix: ARM (infra-pi) and AMD64 (k8s-node-*)

  Proxmox VE hosts the nodes

  MariaDB running directly on bare metal (no container overhead)
```

🖥️ **Node Layout Summary**

| Node       | IP              | Arch  | Role Labels                       |
| ---------- | --------------- | ----- | --------------------------------- |
| `infra-pi` | `192.168.0.10`  | ARM64 | `control-plane`, `pi-hole`        |
| `node-171` | `192.168.0.171` | AMD64 | `control-plane`, `master-ingress` |
| `node-181` | `192.168.0.181` | AMD64 | `control-plane`, `master-ingress` |

🗄️ **MariaDB as External K3s Datastore**

```bash
apt update
apt install mariadb-server -y
systemctl enable mariadb
systemctl start mariadb
```

🔐 **DB Setup**

```bash
CREATE DATABASE k3s;
CREATE USER 'k3suser'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON k3s.* TO 'k3suser'@'%';
FLUSH PRIVILEGES;
```

Update bind address in /etc/mysql/mariadb.conf.d/50-server.cnf to allow external
connections:

```bash
bind-address = 0.0.0.0
```

Restart MariaDB:

```bash
systemctl restart mariadb
```

Test from other nodes:

```bash
mysql -u k3suser -p -h 192.168.0.52 k3s
```

## 📦 K3s + kube-vip for Control Plane VIP

Instead of manual load balancer setup, we run kube-vip as a DaemonSet on each
control-plane node.

⚙️ **Generate kube-vip DaemonSet manifest**

Run this in one of the master node which will create a manifest daemonset in
k3s default manifests folder.

```bash
sudo ctr image pull ghcr.io/kube-vip/kube-vip:v0.8.0
sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:v0.8.0 vip \
  /kube-vip manifest daemonset \
  --interface eth0 \
  --address 192.168.0.100 \
  --controlplane \
  --arp \
  --leaderElection \
  --taint \
  --inCluster | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml > /dev/null
```

✅ This VIP (192.168.0.100) now serves as the HA control-plane endpoint.

## 📶 MetalLB: LoadBalancer for Bare Metal

⚡ **Install MetalLB by Applying the manifest from the Source**

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

🔐 **Create the MetalLB memberlist secret**

```bash
kubectl create secret generic -n metallb-system memberlist \
  --from-literal=secret="$(openssl rand -base64 128)"
```

Apply [MetalLB config](/k3s-ha-cluster/deployments/metallb-config.yaml) to
assign IPs to LoadBalancer services from given `addresses:` in the config file.

📜 **Configure IP Pool**

Apply [MetalLB config](/k3s-ha-cluster/deployments/metallb-config.yaml) to
assign IPs to LoadBalancer services from given `addresses:` in the config file.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-address-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.200-192.168.0.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
```

## 🌐 Caddy Ingress Controller

Caddy handles TLS, routing, and hostname-based services (like pihole.lab.local).

🚀 **Install with Helm**

```bash
helm repo add caddyserver https://caddyserver.github.io/ingress/
helm repo update

helm upgrade --install caddy caddyserver/caddy-ingress-controller \
  --namespace caddy-system \
  -f values.yaml
```

`role=master-ingress` nodeSelector is used to avoid scheduling on the Pi-hole
node.

## 🚫 Pi-hole: Local DNS + Ad Blocker

### pi-hole DNS Nameserver

🧩 **Deploy secrets for admin access**

```bash
kubectl create secret generic pihole-password \
  --from-literal=WEBPASSWORD='admin' \
  -n pihole
```

✅ To persist password across restarts, set WEBPASSWORD from the secret as an
env var. However, volume mounts may still override it
(TODO: resolve Pi-hole config persistency, `/etc/pihole/pihole.toml`).

🐳 **Pi-hole Deployment (simplified excerpt)**

**NOTE** We are creating two different services to pi-hole to answer DNS
queries.

> - `hostNetwork: true` is set so it can bind to DNS (port 53) on the host
> - `dnsPolicy: ClusterFirstWithHostNet` to use cluster DNS correctly
> - Deployed on infra-pi via `nodeSelector: role=pi-hole`

Note:
> For both protocols to work, you need to specify them in different services. On
> MetalLB each service must have a unique IP address.
> This can be fixed by setting the following annotation in both services for
> PiHole
> ref. <https://github.com/pi-hole/docker-pi-hole/issues/862>

```bash
cd k3s-ha-cluster/deployments/pi-hole

kubectl apply -f deployment.yaml
kubectl apply -f service-tcp.yaml
kubectl apply -f service-udp.yaml
```

📡 **Shared IP for TCP/UDP Services**

Both TCP and UDP Services use:

```yaml
annotations:
  metallb.universe.tf/allow-shared-ip: shared
```

and share this IP:

`loadBalancerIP: 192.168.0.202`

This enables:

- `:53` TCP/UDP → DNS
- `:80` → Web UI
- `:443` → SSL (optional)
