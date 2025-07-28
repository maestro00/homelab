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

## Caddy Web Server

Apply deployment and configuration files to put caddy web-server up and running

> **NOTE**: I used an init container to copy my html files to volumes mount path
in my deployment, comment out if you don't need to.

```sh
kubectl apply -f deployment.yaml
kubectl apply -f pvc.yaml
kubectl apply -f configmap.yaml
kubectl apply -f service.yaml
```

If you have static files for your website you can create a config-map from the
file

```sh
kubectl create configmap caddy-html-files \
  --from-file=caddy-web/html/index.html \
  -n caddy-web
```

Go to LoadBalancer IP given by the MetalLB and display your page. To get the IP
address run

```sh
kubectl get svc -n caddy-web -o wide
NAME        TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
caddy-web   LoadBalancer   10.43.136.232   192.168.0.201   80:30145/TCP,443:30695/TCP
```

Hit the `EXTERNAL-IP` and now you'll be seeing the content of your page!

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

## 🐮 Longhorn Block Storage

Longhorn gives us persistent storage accross all nodes for our deployments which
brings highly availability to our services.

I wanted to exclude to using pi4 as storage class since it has only sd card
inserted which could slow down my apps using that in write/read operations. For
that reason, I tainted my `infra-pi` hostnamed node from longhorn deployments.

```bash
kubectl taint nodes infra-pi node-role.kubernetes.io/no-longhorn=:NoSchedule
```

To deploy Longhorn via helm to our selected nodes:

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set persistence.defaultClass=true \
  --set defaultSettings.createDefaultDiskLabeledNodes=true \
  --set defaultSettings.taintToleration="node-role.kubernetes.io/no-longhorn=true:NoSchedule"
```

Label each node to point to default disk labels to be scheduled once the
`longhorn-manager` pods are up and running.

```sh
# repeat this for each node to be used as longhorn storage
kubectl label nodes <my_node> node.longhorn.io/create-default-disk=true
```

I assign LoadBalancer IP `192.168.0.203 for` `longhorn-ui` and applied my
loadbalancer config file with

```bash
kubectl apply -f longhorn/loadbalancer-ui.yaml
```

To get rid of conflict between `multipath` and `longhorn` disable `multipath`
service

```bash
sudo systemctl stop multipathd
sudo systemctl disable multipathd
```

**NOTE**
If you face with the warning `longhorn Kernel modules [dm_crypt] are not loaded`
if not using encryption, it's OK, otherwise you can load the module with

```bash
echo "dm_crypt" | sudo tee -a /etc/modules
```

either restart the node or the manager pod of that node to get updated status in
longhorn UI.

## Tailscale VPN

🛠️ **Step 1: Create a Tailscale Account & Auth Key**

> - Go to <https://tailscale.com>
> - Sign in with Google, GitHub, or email
> - Visit: <https://login.tailscale.com/admin/settings/keys>
> - Click "Generate Key":
> - Type: Reusable key ✅
> - Scopes:
>
> - ✅ ephemeral (optional: good for non-persistent nodes)
> - ✅ preauthorized (optional: skip web login)
> - ✅ Allow exit node and subnet routing (if desired)
>
> Copy the tskey-... auth key and keep it handy (we’ll use it in a Kubernetes Secret)

📦 **Step 2: Create Kubernetes Secret with the Auth Key**

```bash
kubectl create secret generic tailscale-auth \
  -n kube-system \
  --from-literal=TS_AUTHKEY='tskey-...' # Replace with your key
```

Create service account and rbac to allow accessing this secret by our
deployment and apply it.

```bash
kubectl apply -f rbac.yaml
```

Navigate to tailscale folder and apply deployment by configuring your allowed ip
range for `--exit-node`.

```bash
kubectl apply -f deployment.yaml
```

After the deployment is successful, you'll see the added new machine
`k3s-exit-router` in *machines* in tailscale dashboard.

Click on the machine and *Edit* Route Settings, then approve all the routes we
defined in our deployment and check the `Use as exit node` checkbox.

Now you can go to any client, for example your phone (Android & iOS) and

1. Download `tailscale` application from the store
2. Login with the same account you setup tailscale
3. Configure VPN and now you should be seeing your machines
4. Select `k3s-exit-node` as your **EXIT NODE** mark also
**Allow Local Network Access** to be able to get LAN access working.
5. Test an IP address serving a service from your cluster (192.168.0.202 - pihole)
