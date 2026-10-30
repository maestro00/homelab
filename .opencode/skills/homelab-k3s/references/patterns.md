# Deployment Patterns Reference

Common manifest and Helm patterns for yukselcloud.com K3s cluster.

---

## Standard Deployment + Service (raw manifest)

Most services in this cluster follow this pattern — a Deployment with a LoadBalancer Service.

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-service

---
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  namespace: my-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
        - name: my-service
          image: someimage:latest
          ports:
            - containerPort: 8080
          env:
            - name: SOME_VAR
              value: "some-value"
          resources:             # always set limits on homelab — prevents runaway pods
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: my-service-data

---
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: my-service
spec:
  type: LoadBalancer                   # MetalLB picks from pool 192.168.0.200-230
  loadBalancerIP: 192.168.0.225        # pin a specific IP — always do this!
  selector:
    app: my-service
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP

---
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-service-data
  namespace: my-service
spec:
  accessModes:
    - ReadWriteOnce                    # RWO = one node at a time (most services)
    # ReadWriteMany                    # RWX = multiple nodes (use for shared media libs)
  storageClassName: longhorn           # always use longhorn for HA-replicated storage
  resources:
    requests:
      storage: 10Gi
```

---

## Secrets

Use Kubernetes Secrets for passwords, tokens, API keys. Never put them in plain manifests
committed to Forgejo.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-service-secret
  namespace: my-service
type: Opaque
stringData:                            # stringData auto-base64-encodes for you
  password: "mysecretpassword"
  api-key: "someapikey"
```

Reference in a Deployment:
```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-service-secret
        key: password
```

Apply secrets separately and add to `.gitignore` — or use a tool like `sops` or `sealed-secrets`.

---

## ConfigMap

For non-sensitive configuration files or environment variables:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-service-config
  namespace: my-service
data:
  config.yaml: |
    some_setting: true
    another_setting: "value"
```

Mount as a file:
```yaml
volumeMounts:
  - name: config
    mountPath: /config/config.yaml
    subPath: config.yaml              # subPath mounts a single file, not the whole dir
volumes:
  - name: config
    configMap:
      name: my-service-config
```

---

## StatefulSet (for databases / ordered pods)

Used for: vaultwarden, mysql. Key difference from Deployment: stable network identity,
ordered start/stop, volumeClaimTemplates (each pod gets its own PVC).

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: my-db
  namespace: my-db
spec:
  serviceName: my-db-headless          # must match a headless Service
  replicas: 1
  selector:
    matchLabels:
      app: my-db
  template:
    metadata:
      labels:
        app: my-db
    spec:
      containers:
        - name: my-db
          image: postgres:15
          ports:
            - containerPort: 5432
  volumeClaimTemplates:                # each pod gets its own PVC automatically
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: longhorn
        resources:
          requests:
            storage: 5Gi
```

---

## DaemonSet (run on every node)

Used for: authelia, crowdsec-agent, metallb-speaker, kube-vip, node-exporter.
Guarantees one pod per node — useful for node-level agents.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: my-agent
  namespace: my-ns
spec:
  selector:
    matchLabels:
      app: my-agent
  template:
    metadata:
      labels:
        app: my-agent
    spec:
      containers:
        - name: my-agent
          image: myagent:latest
```

---

## Helm Workflow

### Adding a new Helm-deployed service

```bash
# 1. Add the chart repo
helm repo add <repo-name> <repo-url>
helm repo update

# 2. Inspect available values
helm show values <repo-name>/<chart-name> > default-values.yaml

# 3. Create your override values file
# Only include what you're changing — Helm merges with defaults
cat > my-service-values.yaml << 'EOF'
# your overrides here
EOF

# 4. Install (dry-run first)
helm install my-service <repo-name>/<chart-name> \
  --namespace my-service \
  --create-namespace \
  --values my-service-values.yaml \
  --dry-run

# 5. Install for real
helm install my-service <repo-name>/<chart-name> \
  --namespace my-service \
  --create-namespace \
  --values my-service-values.yaml

# 6. Upgrade after changing values
helm upgrade my-service <repo-name>/<chart-name> \
  --namespace my-service \
  --values my-service-values.yaml
```

### Helm values file conventions for this cluster

```yaml
# Always pin image tags — avoid :latest in production
image:
  tag: "1.2.3"

# Always configure service type and pin the LoadBalancer IP
service:
  type: LoadBalancer
  loadBalancerIP: 192.168.0.225       # next available IP

# Always set Longhorn as storageClass for persistent data
persistence:
  enabled: true
  storageClass: longhorn
  size: 10Gi

# Set resource limits
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 1Gi
    cpu: 500m
```

### Useful Helm commands

```bash
helm list --all-namespaces            # all installed releases
helm status my-service -n my-ns      # release status
helm get values my-service -n my-ns  # currently applied values
helm history my-service -n my-ns     # rollback history
helm rollback my-service 1 -n my-ns  # rollback to revision 1
helm uninstall my-service -n my-ns   # remove release
```

---

---

## Media Stack Pattern (Custom Umbrella Helm Chart)

The `media/` folder is a custom umbrella Helm chart where all apps share one
`templates/deployment.yaml` and `templates/service.yaml` but each has its own `values.yaml`.

```bash
# Deploy any single app
helm upgrade --install sonarr ./media -f ./media/sonarr/values.yaml -n media

# Typical values.yaml for a media app
image:
  repository: lscr.io/linuxserver/sonarr
  tag: latest

service:
  type: LoadBalancer
  loadBalancerIP: 192.168.0.212    # pin to a specific MetalLB IP

env:
  PUID: "1000"
  PGID: "1000"
  TZ: "Europe/Helsinki"

volumeMounts:
  - name: config
    mountPath: /config
  - name: tv
    mountPath: /tv
  - name: downloads
    mountPath: /downloads

volumes:
  - name: config
    persistentVolumeClaim:
      claimName: sonarr-config     # references PVC in media/pvc.yaml
  - name: tv
    persistentVolumeClaim:
      claimName: media-tv          # shared NFS PVC
  - name: downloads
    persistentVolumeClaim:
      claimName: media-downloads   # shared NFS PVC
```

PVs and PVCs are managed separately and applied before Helm installs:
```bash
kubectl apply -f media/pv.yaml    # NFS PersistentVolumes (server: 192.168.0.52)
kubectl apply -f media/pvc.yaml   # PVCs for all apps
```

NFS directory structure on server (192.168.0.52 / Proxmox host):
```
/srv/media/
├── downloads/        # qBittorrent active downloads
├── completed/        # completed downloads
├── movies/           # Radarr + Jellyfin
├── tv/               # Sonarr + Jellyfin
└── config/
    ├── jellyfin/
    ├── qbittorrent/
    └── ...
```

---

## Database Patterns

### MySQL (Bitnami Helm, `db` namespace)

```bash
helm upgrade --install mysql oci://registry-1.docker.io/bitnamicharts/mysql \
  --namespace db --values mysql/values.yaml
```

Access internally: `mysql.db.svc.cluster.local:3306`
Access externally: `192.168.0.207:3306`

Adding a new database:
```sql
CREATE DATABASE myapp;
CREATE USER 'myapp'@'%' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON myapp.* TO 'myapp'@'%';
FLUSH PRIVILEGES;
```

Cross-namespace secret pattern (app in different namespace needs DB password):
```bash
# Copy secret to consuming namespace — see security/crowdsec/mysql-secret.yaml
kubectl get secret mysql-secret -n db -o yaml \
  | sed 's/namespace: db/namespace: myapp/' \
  | kubectl apply -f -
```

### CNPG PostgreSQL (Forgejo pattern)

CloudNativePG operator manages PostgreSQL clusters. Forgejo uses this pattern:
```bash
# Apply CNPG operator first
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml

# Then apply the cluster manifest
kubectl apply -f forgejo/postgres/postgres-forgejo.yaml
```

---

## K3s-Specific Notes vs Vanilla Kubernetes

| Topic | Vanilla K8s | K3s (this cluster) |
|-------|-------------|---------------------|
| Default ingress | None | Traefik (disabled — using Caddy instead) |
| Default storage | None | local-path provisioner (Longhorn added manually) |
| Load balancer | None (cloud only) | MetalLB (installed manually) |
| etcd | Separate process | Embedded (or external — check k3s config) |
| kubeconfig | `/etc/kubernetes/admin.conf` | `/etc/rancher/k3s/k3s.yaml` |
| Node token | Various | `/var/lib/rancher/k3s/server/node-token` |
| Manifests auto-apply | No | Yes — drop YAML in `/var/lib/rancher/k3s/server/manifests/` |
| Traefik | Optional | Installed by default — **disabled on this cluster** |

### K3s: Traefik is disabled
This cluster uses Caddy as the ingress controller. Do NOT write Traefik IngressRoute
resources. Use Caddy's Caddyfile ConfigMap for routing instead.
