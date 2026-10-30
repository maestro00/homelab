# kubectl Workflows for yukselcloud.com K3s Cluster

---

## Cluster Health

```bash
kubectl get nodes -o wide                          # node status + IPs
kubectl top nodes                                  # CPU/memory usage per node
kubectl get pods --all-namespaces                  # all pods cluster-wide
kubectl get pods --all-namespaces | grep -v Running  # find non-running pods
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30
```

---

## Namespace Operations

```bash
kubectl get ns                                     # list namespaces
kubectl create namespace my-ns                     # create namespace
kubectl delete namespace my-ns                     # delete namespace + everything in it
kubectl get all -n my-ns                           # everything in a namespace
```

---

## Pod Debugging

```bash
# Logs
kubectl logs -n <ns> <pod-name>                    # current logs
kubectl logs -n <ns> <pod-name> --previous         # logs from crashed previous container
kubectl logs -n <ns> -l app=<label> --tail=100     # logs from all pods matching label
kubectl logs -n <ns> <pod-name> -f                 # follow/stream logs

# Exec into a pod
kubectl exec -it -n <ns> <pod-name> -- /bin/bash
kubectl exec -it -n <ns> <pod-name> -- /bin/sh    # if bash not available

# Describe (events, resource limits, mounts — best first debug step)
kubectl describe pod -n <ns> <pod-name>
kubectl describe node k8s-node-171                 # node events/capacity

# Pod status details
kubectl get pod -n <ns> <pod-name> -o yaml        # full pod spec as applied
```

---

## Deployments

```bash
kubectl get deployment -n <ns>
kubectl rollout restart deployment/<name> -n <ns>  # rolling restart (picks up ConfigMap changes)
kubectl rollout status deployment/<name> -n <ns>   # watch rollout progress
kubectl rollout history deployment/<name> -n <ns>  # revision history
kubectl rollout undo deployment/<name> -n <ns>     # rollback to previous

kubectl scale deployment/<name> --replicas=0 -n <ns>  # stop a service (0 replicas)
kubectl scale deployment/<name> --replicas=1 -n <ns>  # start it back
```

---

## Services & Networking

```bash
kubectl get svc --all-namespaces                   # all services + IPs
kubectl get svc -n <ns>                            # services in namespace
kubectl describe svc -n <ns> <svc-name>            # service details + endpoints

# Check MetalLB IP assignments
kubectl get svc --all-namespaces | grep LoadBalancer

# Test internal DNS resolution from inside the cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup jellyfin.media.svc.cluster.local
```

---

## Storage (Longhorn)

```bash
kubectl get pvc --all-namespaces                   # all PVCs + status + size
kubectl get pv                                     # physical volumes
kubectl describe pvc -n <ns> <pvc-name>            # PVC details + bound volume

# Longhorn UI is available at:
# http://192.168.0.203 (LoadBalancer)
```

---

## ConfigMaps & Secrets

```bash
kubectl get configmap -n <ns>
kubectl edit configmap -n <ns> <name>              # edit in-place
kubectl describe configmap -n <ns> <name>

kubectl get secret -n <ns>
kubectl describe secret -n <ns> <name>             # shows keys but not values
kubectl get secret -n <ns> <name> -o jsonpath='{.data.<key>}' | base64 -d  # decode a value
```

---

## Applying Manifests

```bash
kubectl apply -f manifest.yaml                     # apply (create or update)
kubectl apply -f ./directory/                      # apply all YAMLs in a dir
kubectl delete -f manifest.yaml                    # delete resources from manifest
kubectl diff -f manifest.yaml                      # preview changes before applying
kubectl apply -f manifest.yaml --dry-run=client    # dry-run (no changes applied)
```

---

## Helm

```bash
helm list -A                                       # all releases, all namespaces
helm list -n <ns>                                  # releases in namespace
helm status <release> -n <ns>                      # release health
helm get values <release> -n <ns>                  # currently applied values
helm upgrade <release> <chart> -n <ns> -f values.yaml  # upgrade with new values
helm rollback <release> 1 -n <ns>                  # rollback to revision 1
```

---

## Quick Namespace Cheatsheet (this cluster)

```bash
# Auth stack
kubectl logs -n auth -l app.kubernetes.io/name=authelia --tail=50
kubectl rollout restart daemonset/authelia -n auth

# Caddy
kubectl rollout restart deployment/caddy -n caddy
kubectl logs -n caddy -l app=caddy --tail=50

# Media services
kubectl get pods -n media
kubectl logs -n media deployment/jellyfin

# Monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# then open http://localhost:3000

# Forgejo
kubectl logs -n forgejo deployment/forgejo --tail=50

# Longhorn
kubectl get pods -n longhorn-system | grep -v Running
```

---

## Common Fixes

```bash
# Pod stuck in Pending — usually a PVC or node scheduling issue
kubectl describe pod -n <ns> <pod> | grep -A 10 Events

# Pod stuck in CrashLoopBackOff — check logs from previous crash
kubectl logs -n <ns> <pod> --previous

# ImagePullBackOff — check image name/tag, or registry auth
kubectl describe pod -n <ns> <pod> | grep -A 5 "Failed"

# Config change not picked up — restart the deployment
kubectl rollout restart deployment/<name> -n <ns>

# Force delete a stuck pod
kubectl delete pod -n <ns> <pod> --grace-period=0 --force
```
