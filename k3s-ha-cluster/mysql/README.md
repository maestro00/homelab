# MySQL

MySQL server in the `db` namespace using the Bitnami Helm chart. Used as a backing
several applications.

## Databases (Initial database created during setup)

| Database   | User       | Used by   |
|------------|------------|-----------|
| `crowdsec` | `crowdsec` | CrowdSec  |

## Install

```bash
kubectl create namespace db

# Generate passwords and update secret.yaml
openssl rand -base64 32  # root
openssl rand -base64 32  # replication
openssl rand -base64 32  # crowdsec

kubectl apply -f secret.yaml

helm upgrade --install mysql oci://registry-1.docker.io/bitnamicharts/mysql \
  --namespace db \
  --values values.yaml
```

## Access

- **Cluster**: `mysql.db.svc.cluster.local:3306`
- **External**: `192.168.0.207:3306` (MetalLB)

```bash
MYSQL_ROOT_PASSWORD=$(kubectl get secret mysql-secret \
  -n db -o jsonpath='{.data.mysql-root-password}' \
  | base64 -d)

kubectl run mysql-client --rm -it --restart=Never \
  --image=docker.io/bitnami/mysql:latest --namespace db -- \
  mysql -h mysql.db.svc.cluster.local -uroot -p"$MYSQL_ROOT_PASSWORD"
```

## Adding a New Database

```sql
CREATE DATABASE myapp;
CREATE USER 'myapp'@'%' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON myapp.* TO 'myapp'@'%';
FLUSH PRIVILEGES;
```

If the consuming app is in a different namespace, create a copy of the password
secret there
(see [crowdsec/mysql-secret.yaml](../security/crowdsec/mysql-secret.yaml)
for an example).
