# Speedtest Tracker Deployment (Kubernetes)

Speedtest Tracker is a self-hosted application that periodically runs internet
speed tests and stores the results for visualization and monitoring.

## Architecture

Speedtest Tracker runs as a single container and connects to the shared MySQL database.

Speed tests are scheduled every **30 minutes** using the internal scheduler.

---

## Environment Configuration

Key environment variables used:

| Variable           | Description                                        |
| ------------------ | -------------------------------------------------- |
| APP_KEY            | Laravel encryption key (must start with `base64:`) |
| APP_TIMEZONE       | Application timezone                               |
| DISPLAY_TIMEZONE   | Timezone used in UI                                |
| DB_CONNECTION      | Database driver (`mysql`)                          |
| DB_HOST            | MySQL service hostname                             |
| DB_DATABASE        | Database name                                      |
| DB_USERNAME        | Database user                                      |
| DB_PASSWORD        | Database password                                  |
| SPEEDTEST_SCHEDULE | Cron schedule for tests                            |
| SPEEDTEST_SERVERS  | Preferred Speedtest server IDs                     |

Example configuration:

```bash
APP_TIMEZONE=Europe/Helsinki
DISPLAY_TIMEZONE=Europe/Helsinki
SPEEDTEST_SCHEDULE=*/30 * * * *
SPEEDTEST_SERVERS=22669,14928,14164,32643
```

---

## Deployment

A dedicated database and user were created in the MySQL cluster.

Example SQL:

```sql
CREATE DATABASE speedtest_tracker;

CREATE USER 'speedtest'@'%' IDENTIFIED BY '<mysecurepassword>';

GRANT ALL PRIVILEGES ON speedtest_tracker.* TO 'speedtest'@'%';

FLUSH PRIVILEGES;
```

```bash
kubectl apply -f speedtest-tracker/
```

---

## Accessing the Application

The application is exposed through a **LoadBalancer service**.

Example access URL:

```bash
http://<LoadBalancer-IP>
```

---

## First Login

Default credentials:

```bash
Username: admin@example.com
Password: password
```

After logging in:

1. Open **Settings → Users**
2. Change the **email/username**
3. Change the **password**

## Visualization

Metrics are exported by enabling the prometheus from settings in UI and frames are
exported via [service-monitor](../monitoring/service-monitor/speedtest-tracker.yaml).
