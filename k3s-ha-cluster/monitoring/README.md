# Monitoring (Prometheus/Grafana)

This directory holds Helm values and instructions for deploying the
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
(prometheus, node-exporter, alertmanager, grafana, etc.) into the cluster.

## Installation

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl apply -f monitoring/grafana-admin-secret.yaml

helm upgrade --install prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/values.yaml
```

## Customising

Edit `values.yaml` to change storage sizes, enable ingress, set Grafana
credentials, etc.  Values are passed directly through to the upstream chart.

## Scraping extra targets

```yaml
# example ServiceMonitor for a service in the "demo" namespace
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-web
  namespace: monitoring
  labels:
    release: prometheus    # corresponds to the helm release name
spec:
  selector:
    matchLabels:
      app: demo-web
  namespaceSelector:
    matchNames:
      - demo-website
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Alternatively, add annotations to your Deployment/Service pods:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: /metrics
    prometheus.io/port: "8080"
```

These annotations are picked up by the default `ServiceMonitor` shipped in
`kube-prometheus-stack`.
