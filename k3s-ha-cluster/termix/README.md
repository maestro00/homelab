# Termix SSH Web Terminal

Termix is a web-based SSH terminal manager that allows you to manage and
connect to SSH servers through a browser interface.

## 📦 Installation

### Using Helm

Install the chart:

```bash
helm install termix ./termix
```

## 🌐 Access

After deployment, get the external IP assigned by MetalLB:

```bash
kubectl get svc -n termix termix
```

Then access Termix at `http://<EXTERNAL-IP>:8080`

## 🔍 Monitoring

## 📚 Documentation

- [Official Docs](https://docs.termix.site)
- [GitHub](https://github.com/Termix-SSH/Termix)
