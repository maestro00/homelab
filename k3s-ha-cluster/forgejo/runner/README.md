# Forgejo Runner Helm Chart

Auto-registering Forgejo Actions Runner for Kubernetes.

## Installation Steps

### 1. Register Runner on Forgejo Server

On your Forgejo instance, run:

```bash
forgejo forgejo-cli actions register \
  --secret <some_secret> \
  --name k8s-runner-1 \
  --scope <your-scope>
```

Replace `<your-scope>` with:

- No `--scope`: register for all repos (admin)
- `--scope my-org`: register for organization
- `--scope owner/repo`: register for single repo

### 2. Create Kubernetes Secret

```bash
kubectl create secret generic forgejo-runner-token \
  --from-literal=runner-token=<some_secret> \
  -n forgejo
```

### 3. Deploy Helm Chart

```bash
helm upgrade --install forgejo-runner . -n forgejo
```

The init container will auto-register using the hex secret.

## Configuration

Edit `values.yaml`:

- `runner.instanceUrl`: Your Forgejo instance URL
- `runner.name`: Runner name
- `runner.labels`: Job labels (comma-separated)
- `secret.token`: Must be a 40-char hex string (register on server first)

## Notes

- The `.runner` config file persists in the PVC
- Delete the PVC to force re-registration
- Docker socket is mounted from host (for job containers with docker)
