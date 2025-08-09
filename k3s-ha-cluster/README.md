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
  2x worker nodes: k8s-node-172, k8s-node-182

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
| `node-172` | `192.168.0.172` | AMD64 |                                   |
| `node-182` | `192.168.0.182` | AMD64 |                                   |

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

## 🌐 Caddy

Caddy is used as the Ingress Controller to handle TLS, routing, and hostname-based
services (like demo.yukselcloud.com and pihole.yukselcloud.com).

### 🚀 Deploying Caddy Ingress

This repo provides manifests for deploying Caddy as an ingress controller. The
deployment is configured to run only on nodes labeled with `role=master-ingress`
and exposes HTTP/HTTPS via a LoadBalancer service.

**Deployment steps:**

```bash
kubectl create namespace caddy
kubectl apply -f caddy/configmap.yaml
kubectl apply -f caddy/pvc.yaml
kubectl apply -f caddy/deployment.yaml
kubectl apply -f caddy/service.yaml
```

- The `configmap.yaml` contains the Caddyfile with routing rules for your domains.
- The `pvc.yaml` creates a PersistentVolumeClaim using Longhorn for Caddy's
`/data` directory.
- The `deployment.yaml` sets up the Caddy pods with a nodeSelector for
`role: master-ingress` and mounts the PVC at `/data`.
- The `service.yaml` exposes Caddy on ports 80 and 443 using a LoadBalancer, so
MetalLB will assign an external IP.

You can check the assigned external IP with:

```bash
kubectl get svc -n caddy -o wide
```

Example output:

```text
NAME    TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
caddy   LoadBalancer   10.43.136.232   192.168.0.201   80:30145/TCP,443:30695/TCP
```

Visit the `EXTERNAL-IP` in your browser to access your routed services.

To make my websites publicly, I added this EXTERNAL-IP to my Router's NAT Port
forwarding for the ports `80` and `443`, so once the Public IP is promoted to cloudflare,
the requests are forwarded to my caddy ingress.

### 📝 Customizing Caddyfile

Edit `deployments/caddy/configmap.yaml` to add or change domain routing rules.
For example:

```yaml
data:
  Caddyfile: |
    demo.yukselcloud.com {
        reverse_proxy demo-service.caddy-web-demo.svc.cluster.local:80
    }
    caddy-web.yukselcloud.com {
        reverse_proxy caddy-web.caddy-web.svc.cluster.local:80
    }
```

Apply changes with:

```bash
kubectl apply -f deployments/caddy/configmap.yaml
kubectl rollout restart deployment caddy -n caddy
```

> **Note:** The Caddy deployment uses a persistent volume claim (PVC) backed by
Longhorn for `/data` and mounts the config from the ConfigMap.
Adjust the `nodeSelector` or `replica` count as needed in `deployment.yaml`.

## Cloudfare Setup for Using our Domain

Create an API token from Cloudfare profile page and select your `Zone Resources`
points to your domain. Using the api token create a secret in our new namespace
to keep our `A Record`s of domains' updated automatically with our Public IP.

I deployed a Cloudflare Dynamic DNS Updater from community which works like a
charm. Install following the section for
[Deployment on Kubernetes](https://github.com/timothymiller/cloudflare-ddns/?tab=readme-ov-file#-kubernetes)

Create your `config.json` according to readme and apply it.

```bash
kubectl create namespace ddns
kubectl create secret generic config-cloudflare-ddns \
  --from-file=ddns/config.json \
  --dry-run=client -oyaml -n ddns > config-cloudflare-ddns-Secret.yaml
kubectl apply -f config-cloudflare-ddns-Secret.yaml
kubectl apply -f deployment.yaml
```

Now I can see in my logs that it creates a `A Record` in my cloudflare domain.

```txt
➕ Adding new record {
  'type': 'A',
  'name': 'caddy.yukselcloud.com',
  'content': '12.123.123.123',
  'proxied': False,
  'ttl': 3600
}
```

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
  --set defaultSettings.defaultDataLocality=best-effort \
  --set defaultSettings.createDefaultFilesystemVolumeRWX=true \
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

## 🔑 Keycloak - Central Authentication

Keycloak provides central authentication for our services via OAuth2 / OIDC / SAML.

Install it via helm

```bash
kubectl create namespace keycloak
kubectl create secret generic keycloak-secret \
  --from-literal=admin-password=password \ # By default admin username is 'user'
  -n keycloak

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install keycloak bitnami/keycloak \
  --namespace keycloak \
  -f keycloak/values.yaml
```

### Keycloak Setup

To create our Realm and clients via Rest API, get `svc` LoadBalancer IP and
obtain an API token for your user.

```bash
kubectl get svc -n keycloak
NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
keycloak                 LoadBalancer   10.43.215.69   192.168.0.204   80:31215/TCP
keycloak-headless        ClusterIP      None           <none>          8080/TCP
keycloak-postgresql      ClusterIP      10.43.52.242   <none>          5432/TCP
keycloak-postgresql-hl   ClusterIP      None           <none>          5432/TCP
```

Use [keycloak/setup_realm.sh](/k3s-ha-cluster/keycloak/setup_realm.sh) to bootstrap
a new realm named `homelab`.

Create a client by updating `CLIENT_NAME` and `CLIENT_DOMAIN` environment variables
in [keycloak/create_client.sh](/k3s-ha-cluster/keycloak/create_client.sh) to be
used in our authentication services.

> **Note**: To add DNS record in cloudflare, update your `config.json` and generate
a new secret. After that, restart your ddns pod to add your record immediately before
the actual `ttl`.

## ☁️ Nextcloud on Kubernetes

This deployment uses the official
[Nextcloud Helm chart](https://github.com/nextcloud/helm) with full OpenID
Connect (OIDC) integration via Keycloak, optional external MariaDB and Redis
support, and production-readiness features like PVC persistence and support for
scaling (with some caveats).

---

### 🔐 OIDC Configuration

Before deploying, create a Kubernetes secret containing your OIDC credentials
from Keycloak:

```bash
kubectl create namespace nextcloud
kubectl apply -f nextcloud/secret.yaml
```

Create kubernetes secret for OICD credentials, find `CLIENT_ID` and
`CLIENT_SECRET` either from UI or using API.

```bash
kubectl create namespace nextcloud
kubectl apply -f nextcloud/secret.yaml
```

Then, apply a custom ConfigMap that modifies the login redirection to point to
your OIDC provider:

```bash
kubectl apply -f nextcloud/configmap.yaml
```

Your nextcloud/secret.yaml should look like:

```bash
apiVersion: v1
kind: Secret
metadata:
  name: nextcloud-oidc-secret
  namespace: nextcloud
type: Opaque
stringData:
  OIDC_CLIENT_ID: myclientid
  OIDC_CLIENT_SECRET: myclientsecret
  OIDC_ISSUER_URL: https://keycloak.example.com/realms/myrealm
```

The Helm chart is configured to read these values and enable the oidc_login
Nextcloud app automatically.

### ☸️ Install via Helm

```bash
helm repo add nextcloud https://nextcloud.github.io/helm/
helm repo update

helm upgrade --install nextcloud nextcloud/nextcloud \
  -f nextcloud/values.yaml \
  -n nextcloud
```

### 🧠 Redis and Database

You can use the built-in MariaDB (`mariadb.enabled=true`) for testing, or configure
externalDatabase to connect to an external MariaDB instance for production.

Redis is optional but strongly recommended for performance and locking. Enable
it via `redis.enabled=true` in your [values.yaml](/k3s-ha-cluster/nextcloud/values.yaml).

### 📱 Mobile Client Support (iOS/Android)

Since the OIDC login flow disables the native login endpoints (`/login/v2/poll`),
the mobile apps will not log in using the default browser OIDC flow.

Instead:

1. Log into the web UI
2. Go to Settings → Security
3. Generate a new App Password
4. Use the generated credentials in your iOS/Android Nextcloud app

## 🛡️ Vaultwarden

Vaultwarden is deployed for self-hosted password management, with secure admin
access and OIDC authentication via Keycloak.

- Generated a strong `ADMIN_TOKEN` using:

  ```bash
  openssl rand -hex 32
  ```

  and stored it as a Kubernetes secret referenced in [values.yaml](/k3s-ha-cluster/vaultwarden/values.yaml).

- Installed using a community Helm chart:

  ```bash
  helm repo add vaultwarden https://guerzon.github.io/vaultwarden
  helm repo update
  helm install vaultwarden vaultwarden/vaultwarden \
    -n vaultwarden --create-namespace \
    -f vaultwarden/values.yaml
  ```

**Ingress with Caddy:**
Added the following entry to `deployments/caddy/configmap.yaml` to route traffic
for Vaultwarden:

```caddyfile
vaultwarden.yukselcloud.com {
    reverse_proxy 192.168.0.206:80 # you can use svc address as well
}
```

Apply changes and restart Caddy deployment:

```bash
kubectl apply -f deployments/caddy/configmap.yaml
kubectl rollout restart deployment caddy -n caddy
```

**DNS Record with DDNS:**
Update your config.json file by adding new entry

  ```bash
  {
      "name": "vaultwarden",
      "proxied": false
  }
  ```

and generate a new kubernetes secret and apply it.

```bash
kubectl create secret generic config-cloudflare-ddns \
  --from-file=../temp/config.json \
  --dry-run=client -oyaml -n ddns > config-cloudflare-ddns-Secret.yaml

kubectl apply -f config-cloudflare-ddns-Secret.yaml
```

Restart deployment or recreate pods to apply the change immediately.

## 🔒 Tailscale VPN

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
