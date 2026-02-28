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
    - 192.168.0.200-192.168.0.229
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

## 🚫 Pi-hole: Local DNS (Unbound) + Tailscale

To reduce network overhead, I run Pi-hole, Unbound, and Tailscale directly on
the bare-metal RPi4.

```bash
curl -sSL https://install.pi-hole.net | bash

# During setup:
# choose: eth0
# Upstream DNS → choose Custom 127.0.0.1#5335
```

Then install Unbound:

```bash
sudo apt update
sudo apt install unbound -y

# create custom config file and paste it
sudo nano /etc/unbound/unbound.conf.d/pi-hole.conf

server:
    verbosity: 0
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    root-hints: "/var/lib/unbound/root.hints"
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
```

Download root hints and restart Unbound:

```bash
sudo wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
sudo systemctl restart unbound
sudo systemctl enable unbound
```

Install Tailscale on the RPi4 (Bullseye-based):

```bash
sudo apt-get install apt-transport-https
TS_BASE_URL="https://pkgs.tailscale.com/stable/raspbian"
curl -fsSL "$TS_BASE_URL/bullseye.noarmor.gpg" \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
curl -fsSL "$TS_BASE_URL/bullseye.tailscale-keyring.list" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update
sudo apt-get install tailscale
```

After installation, advertise the LAN route and exit node:

```bash
sudo tailscale up --advertise-exit-node \
  --advertise-routes=192.168.0.0/24 --accept-dns=false --reset
```

After it starts successfully, you'll see a new machine named
`k3s-exit-router` in the *Machines* section of the Tailscale dashboard.

Open that machine, click *Edit route settings*, approve the advertised routes,
and enable `Use as exit node`.

Now, on any client device (for example Android or iOS):

1. Install the `Tailscale` app.
2. Sign in with the same account.
3. Connect and confirm your machines are visible.
4. Select `k3s-exit-node` as your **exit node**, and enable
   **Allow local network access**.
5. In DNS settings, add your Pi's Tailscale IP (`100.x.x.x`) as the nameserver.

## 🐮 Longhorn Block Storage

Longhorn gives us persistent storage accross all nodes for our deployments which
brings highly availability to our services.

I wanted to exclude to using pi4 as storage class since it has only sd card
inserted which could slow down my apps using that in write/read operations. For
that reason, I tainted my `infra-pi` hostnamed node from longhorn deployments.

```bash
kubectl taint nodes infra-pi node-role.kubernetes.io/no-longhorn=:NoSchedule
```

I tainted my other nodes with `storage-with-longhorn=true` since some
deployments doesn't accept `taintToleration`, rather expects a label to match.

```bash
kubectl label node k8s-node-171 storage-with-longhorn=true
kubectl label node k8s-node-172 storage-with-longhorn=true
kubectl label node k8s-node-181 storage-with-longhorn=true
kubectl label node k8s-node-182 storage-with-longhorn=true
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

helm upgrade --install keycloak bitnami/keycloak \
  --namespace keycloak \
  -f keycloak/values.yaml
```

### Keycloak Setup

To create our Realm and clients via Rest API, get `svc` LoadBalancer IP and
obtain an API token for your user.

```bash
kubectl get svc -n keycloak
NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
keycloak                 LoadBalancer   10.43.215.69   192.168.0.202   80:31215/TCP
keycloak-headless        ClusterIP      None           <none>          8080/TCP
keycloak-postgresql      ClusterIP      10.43.52.242   <none>          5432/TCP
keycloak-postgresql-hl   ClusterIP      None           <none>          5432/TCP
```

Login with default admin user and credentials you defined in the `keycloak-secret`.
Create a permanent admin user and assign all the admin roles. Then, delete the
initial temporary admin user by the new admin.

Use [keycloak/setup_realm.sh](/k3s-ha-cluster/keycloak/setup_realm.sh) to bootstrap
a new realm named `homelab`.

Create a client by updating `CLIENT_NAME` and `CLIENT_DOMAIN` environment variables
in [keycloak/create_client.sh](/k3s-ha-cluster/keycloak/create_client.sh) to be
used in our authentication services.

> **Note**: To add DNS record in cloudflare, update your `config.json` and generate
a new secret. After that, restart your ddns pod to add your record immediately before
the actual `ttl`.

## ☁️ Nextcloud on Kubernetes (Deprecated)

This deployment uses the official
[Nextcloud Helm chart](https://github.com/nextcloud/helm) with full OpenID
Connect (OIDC) integration via Keycloak, optional external MariaDB and Redis
support, and production-readiness features like PVC persistence and support for
scaling (with some caveats).

---

### 🔐 OIDC Configuration

Before deploying, create a Kubernetes secret for OICD credentials, find
`CLIENT_ID` and `CLIENT_SECRET` either from UI or using API.

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

Create a longhorn backed PVC for a space you need, to support replicas, apply
storage `accessModes` as `ReadWriteMany`.

```bash
kubectl apply -f nextcloud/pvc.yaml
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
  helm upgrade --install vaultwarden vaultwarden/vaultwarden \
    -n vaultwarden --create-namespace \
    -f vaultwarden/values.yaml
  ```

**Ingress with Caddy:**
Added the following entry to `deployments/caddy/configmap.yaml` to route traffic
for Vaultwarden:

```caddyfile
vaultwarden.yukselcloud.com {
    reverse_proxy 192.168.0.204:80 # you can use svc address as well
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

## 📄 Paperless-ngx: Document Management (Deprecated)

Paperless-ngx is a powerful self-hosted document management solution.
This section guides you through deploying Paperless-ngx on Kubernetes with Redis
and persistent storage.

### 1️⃣ Deploy Redis

Create a Redis password secret:

```bash
kubectl create secret generic redis-secret \
  --from-literal=redis-password="maestroredispaperless" \
  --namespace=paperless
```

Install Redis using the Bitnami Helm chart:

```bash
helm install paperless-redis bitnami/redis \
  -n paperless \
  --create-namespace \
  -f paperless-ngx/redis/values.yaml
```

Get the Redis service name and connection details:

```bash
kubectl get svc -n paperless

NAME                       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
paperless-redis-headless   ClusterIP   None         <none>        6379/TCP   21h
paperless-redis-master     ClusterIP   10.43.4.92   <none>        6379/TCP   21h
```

Compose your `PAPERLESS_REDIS` environment variable using the service name:

```text
redis://:<password>@paperless-redis-master.paperless.svc.cluster.local:6379
```

### 2️⃣ Deploy Persistent Storage

Apply the PVC manifest to provide persistent storage for Paperless-ngx:

```bash
kubectl apply -f paperless-ngx/pvc.yaml
```

### 3️⃣ Deploy Paperless-ngx

Apply the deployment manifest:

```bash
kubectl apply -f paperless-ngx/deployment.yaml
```

### 4️⃣ Expose Paperless-ngx Service

Expose Paperless-ngx via a LoadBalancer service:

```bash
kubectl apply -f paperless-ngx/service.yaml
```

Check the assigned external IP:

```bash
kubectl get svc -n paperless -o wide
```

Access Paperless-ngx at `http://<EXTERNAL-IP>`.

---

**Notes:**

- The deployment uses Longhorn for persistent storage.
- Redis is required for optimal performance and locking.
- OIDC authentication can be configured via Keycloak for SSO.
- Update environment variables in the deployment manifest as needed for your setup.

## 📊 Kubernetes Dashboard

Kubernetes Dashboard provides a web-based UI for managing and monitoring your cluster.

### 1️⃣ Install via Helm

Add the Helm repo and install the dashboard:

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard \
  -f kubernetes-dashboard/values.yaml
```

### 2️⃣ Configure Access

Apply the pre-created ServiceAccount and RBAC configuration for admin access:

```bash
kubectl apply -f kubernetes-dashboard/service-account.yaml
kubectl apply -f kubernetes-dashboard/rbac.yaml
```

### 3️⃣ Get Login Token

Retrieve the login token for the dashboard:

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

Access the dashboard at `https://<EXTERNAL-IP>` (see the service details).

---

**Notes:**

- The dashboard is exposed via a LoadBalancer service.
- Use the generated token for admin login.

## 🏠 Homer Dashboard

Homer is a simple, static dashboard for your homelab services.

### Install via Helm

Add the Homer Helm repo and install:

```bash
helm repo add djjudas21 https://djjudas21.github.io/charts/
helm repo update djjudas21

helm upgrade --install homer djjudas21/homer \
  --create-namespace \
  -n homer \
  -f homer/values.yaml
```

### Configure Homer

Create a ConfigMap referencing your dashboard configuration:

```bash
kubectl -n homer create configmap homer-config \
  --from-file=config.yml=homer/config.yaml \
  -o yaml --dry-run=client | kubectl apply -f -
```

---

**Notes:**

- Homer is exposed via a LoadBalancer service (see `homer/values.yaml`).
- Update `homer/config.yaml` to customize your dashboard links and appearance.

## 🛠️ Forgejo: Self-hosted Git Service

Forgejo provides a lightweight, self-hosted Git platform with Keycloak SSO.

### 🚀 Deploy Forgejo

```bash
kubectl create namespace forgejo

# Install CNPG operator
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml

# Deploy PostgreSQL resources
kubectl apply -f forgejo/postgres/forgejo-db-app.yaml
kubectl apply -f forgejo/postgres/cnpg-superuser.yaml
kubectl apply -f forgejo/postgres/postgres-forgejo.yaml

# Deploy Forgejo secrets
kubectl apply -f forgejo/admin-secret.yaml

# Generate randoms one by one, e.g. head -c32 /dev/urandom | base64
kubectl apply -f forgejo/internal.yaml

# Install Forgejo via Helm
helm upgrade --install forgejo \
  oci://code.forgejo.org/forgejo-helm/forgejo \
  --namespace forgejo \
  --version 15.0.3 \
  -f forgejo/values.yaml
```

### 🤖 Deploy Forgejo Runner (CI/CD)

For Actions Runner setup, see [forgejo/runner/README.md](forgejo/runner/README.md).

Quick steps:

```sh
# Register runner on Forgejo server
forgejo forgejo-cli actions register --secret <hex> --name k8s-runner-1
kubectl create secret generic \
  forgejo-runner-token \
  --from-literal=runner-token=<hex> -n forgejo
helm upgrade --install forgejo-runner ./forgejo/runner -n forgejo
```

#### Forgejo + GitHub Dual-Repository Workflow

##### Overview

This project uses **Forgejo (private)** for development and **GitHub (public)**
as a curated mirror.

###### Goals

- Forgejo is the primary development repository
- Feature branches never go to GitHub
- Only `master` is pushed to GitHub
- Forgejo issues and automation are the source of truth
- No accidental public pushes

---

##### Repository Roles

| Repository | Purpose                                  |
|------------|------------------------------------------|
| Forgejo    | Development, feature branches, issues    |
| GitHub     | Public mirror (`master` only)            |

---

##### Remote Configuration

Forgejo is the default remote (`origin`). GitHub is explicit.

```bash
git remote remove origin 2>/dev/null || true
git remote remove github 2>/dev/null || true

git remote add origin https://git.yukselcloud.com/lab/homelab.git
git remote add github https://github.com/maestro00/homelab.git
```

**Note**: Allow pushing only master to GitHub avoiding many branches everywhere:

```bash
git config remote.github.push '!refs/heads/*'
git config --add remote.github.push refs/heads/master
```

##### Development Workflow

```bash
git checkout master
git pull origin master
git checkout -b feature/XX-description
git commit
# Deploy lldap to home cluster
# Fixes #2
#
git push -u origin feature/XX-description
git checkout master
git merge feature/XX-description
```

### Auth

Architecture

```txt
Browser
 └─ Caddy (192.168.0.201)
     └─ forward_auth → Authelia
         └─ LDAP → lldap
     └─ App (Radarr, Sonarr, etc.)
```

```bash
helm repo add authelia https://charts.authelia.com
helm repo update
```

Create secrets for authelia by following and paste them in the
[secret.yaml](/k3s-ha-cluster/auth/authelia/secret.yaml).

```sh
echo "OIDC_HMAC_KEY: $(openssl rand -base64 48)"
echo "RESET_ENCRYPTION_KEY: $(openssl rand -base64 48)"
echo "SESSION_ENCRYPTION_KEY: $(openssl rand -base64 32 | head -c 32)"
echo "STORAGE_ENCRYPTION_KEY: $(openssl rand -base64 32 | head -c 32)"

kubectl apply -f auth/authelia/secret.yaml
```

Create clients in [values.yaml](/k3s-ha-cluster/auth/authelia/values.yaml) clients
section and configure their secrets.
Use following to create hash of your super secret by authelia image.

```sh
docker run --rm docker.io/authelia/authelia:latest authelia \
  crypto hash generate pbkdf2 --password 'mysupersecretpassword'
```

Lastly, run helm install command to deploy authelia helm chart.

```sh
helm upgrade
  --install authelia authelia/authelia \
  -n auth \
  --values auth/authelia/values.yaml
```

In the client side, example in forgejo, configure ssh authentication source for
Authelia. Provide at least following parameters:

- Client ID,
- Client Secret (In plain format what pasted in `values.yaml`),
- OpenID Connect Auto Discovery URL (e.g. <https://auth.yukselcloud.com/.well-known/openid-configuration>)
- Skip Local 2FA (checked),
- Additional scopes: `groups`

#### 🔐 Keycloak SSO Integration

- Create a Keycloak client named `forgejo` in your `homelab` realm.
- In Forgejo UI:
  Site Administration → Authentication Sources → Add OAuth2
  - Name: Keycloak
  - Provider: OpenID Connect
  - Client ID/Secret: from Keycloak
  - Discovery URL: `https://keycloak.yukselcloud.com/realms/homelab/.well-known/openid-configuration`
  - Enable Auto Registration
In Forgejo UI (as admin → Site Administration → Authentication Sources → Add OAuth2):

> Name: Keycloak
> OAuth2 provider: OpenID Connect
> Client ID/Secret: # copy from Keycloak
> OpenID Connect Auto Discovery URL: <https://keycloak.yukselcloud.com/realms/homelab/.well-known/openid-configuration>

Enable Auto Registration: ✅

#### LLDAP

TBD:

```sh
kubectl create namespace auth
helm install lldap ./auth/lldap -n auth

```

## 📺 Media Server Stack (Sonarr, Radarr, Prowlarr, Bazarr, Jellyfin, Flaresolverr)

A unified Helm-based deployment for media applications(a.k.a *arr stack) sharing
common storage and networking.

### 🛠️ Prerequisites Setup

#### 1️⃣ Create StorageClass (media-nfs)

Define an NFS-backed StorageClass for persistent storage:

```bash
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: media-nfs
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

This StorageClass enables `PersistentVolumeClaims` to bind to NFS paths on your
storage server.

#### 2️⃣ Create Namespace

```bash
kubectl create namespace media
```

#### 3️⃣ Prepare NFS Storage Paths

On your NFS server (for me PVE. 192.168.0.52), create the directory structure:

```bash
mkdir -p /srv/media/{downloads,completed,movies,tv,config,config/jellyfin,config/qbittorrent,config/vpn}
```

**Directory breakdown:**

- `downloads/` - Active downloads (qBittorrent)
- `completed/` - Completed downloads (qBittorrent)
- `movies/` - Movie library (Radarr, Jellyfin)
- `tv/` - TV shows library (Sonarr, Jellyfin)
- `config/*` - Application configs (mounted as hostPath or PVC)

If using WireGuard VPN, place your config at:

```bash
/srv/media/config/wg_confs/wg0.conf
```

#### 4️⃣ Create PersistentVolumes and PersistentVolumeClaims

```bash
kubectl apply -f media/pv.yaml
kubectl apply -f media/pvc.yaml
```

### 📦 Helm Deployment

The media Helm chart is organized as:

```txt
media/
├── Chart.yaml
├── templates/
│   ├── deployment.yaml
│   └── service.yaml
├── pv.yaml              # PersistentVolume definitions
├── pvc.yaml             # PersistentVolumeClaim definitions
├── sonarr/values.yaml   # TV Shows (DVR)
├── radarr/values.yaml   # Movies (DVR)
├── bazarr/values.yaml   # Subtitles
├── prowlarr/values.yaml # Indexer Aggregator
├── flaresolverr/values.yaml # CAPTCHA Solver
└── jellyfin/values.yaml # Media Server
```

Each app has its own `values.yaml` with:

- Image and version
- Service LoadBalancer IP
- Resource requests/limits
- Environment config
- Volume mounts (references existing PVCs)

#### Deploy Individual Apps

**Deploy all apps:**

```bash
cd k3s-ha-cluster

helm upgrade \
  --install <app_name> \
  ./media -f \
  ./media/<app_name>/values.yaml \
  -n media

# Example: Sonarr
helm upgrade \
  --install sonarr \
  ./media -f \
  ./media/sonarr/values.yaml \
  -n media
```

### 🔧 Configuration & Access

**Sonarr** → `http://192.168.0.212:8989` - TV show management
**Radarr** → `http://192.168.0.213:7878` - Movie management
**Bazarr** → `http://192.168.0.214:6767` - Subtitle management
**Prowlarr** → `http://192.168.0.211:9696` - Indexer management
**Flaresolverr** → `http://192.168.0.217:8191` - CAPTCHA solving
**Jellyfin** → `http://192.168.0.215:8096` - Media playback
**Seerr** → `http://192.168.0.218:5055` - Media request management
**Profilarr** → `http://192.168.0.219:6868` - Media profile management

### 🔄 qBittorrent with Gluetun VPN

qBittorrent is deployed separately with **Gluetun** sidecar container to route traffic
through a VPN. This provides:

- **Privacy:** All torrent traffic encrypted through VPN tunnel
- **IP Masking:** External IP differs from home network
- **Firewall:** Gluetun's built-in firewall blocks non-VPN traffic
- **Killswitch:** Container stops if VPN connection drops

#### Deploy qBittorrent + Gluetun

```bash
kubectl apply -f media/qbittorrent/deployment.yaml
kubectl apply -f media/qbittorrent/service.yaml
```

---

**Notes:**

- Each app references existing PVCs by name (no PV/PVC templates in Helm)
- PV/PVC are managed separately via `kubectl apply` to preserve existing data
- All apps use `media-nfs` StorageClass for shared library access
- LoadBalancer IPs are configured per app in its `values.yaml`
- qBittorrent is deployed separately (requires multi-container setup)
