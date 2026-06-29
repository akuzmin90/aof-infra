# Dedicated Server Alloy

This folder contains Grafana Alloy configs and runbooks for non-Kubernetes servers that push logs into the cluster Loki stack.

These servers are outside Kubernetes, so this is intentionally not under `k8s/`. The cluster receiving side is still managed in `k8s/selectel`:

- Grafana URL: `https://grafana.k8s.zazer.fun`
- Loki push endpoint: `https://grafana.k8s.zazer.fun/loki/api/v1/push`
- Receiver in cluster: `observability/alloy-gateway`
- Auth: nginx basic auth on the push endpoint

## Files

- `kayra/config.alloy` - current Kayra-style config: host `dev` logs plus Docker `feature` and `release` logs.
- `prod/config.alloy` - production host-only config for Tomcat and PostgreSQL logs.
- `templates/host-only.config.alloy` - template for a production server without Docker.
- `install-ubuntu.md` - install and operate Alloy on Ubuntu/Debian hosts.
- `scripts/install-alloy-ubuntu.sh` - install Alloy package.
- `scripts/configure-prod-alloy.sh` - write production config and restart Alloy.

## Labels

All dedicated-server logs should use these Loki labels:

| Label | Meaning | Example |
| --- | --- | --- |
| `source` | Fixed source marker | `dedicated` |
| `host` | Stable server name | `kayra`, `prod` |
| `env` | Stand/environment | `dev`, `feature`, `release`, `prod` |
| `service` | Log-producing service | `tomcat`, `postgres`, `nginx` |

Keep label cardinality low. Do not put request IDs, user IDs, IPs, paths, or error messages into labels; those belong in log lines.

## Secrets

Do not commit the Loki basic auth password.

Get it from OpenTofu:

```powershell
cd k8s/selectel
tofu output -raw dedicated_logs_basic_auth_username
tofu output -raw dedicated_logs_basic_auth_password
```

In configs, replace:

```text
__DEDICATED_LOGS_PASSWORD__
```

with the real password on the server only.

## Production Host Setup

Get the password on your machine:

```powershell
cd k8s/selectel
tofu output -raw dedicated_logs_basic_auth_password
```

On the production server:

```bash
export DEDICATED_LOGS_PASSWORD='paste-password-here'

sudo bash install-alloy-ubuntu.sh
bash configure-prod-alloy.sh
```

If Grafana APT is blocked, copy the Alloy `.deb` to the server and install with:

```bash
export ALLOY_DEB_PATH=/tmp/alloy-1.17.0-1.amd64.deb
sudo bash install-alloy-ubuntu.sh
```

The production config sends:

```text
/opt/apache-tomcat-9.0.21/logs/catalina.out -> service=tomcat
/var/log/postgresql/*.log                  -> service=postgres
```

## Useful Queries

Kayra feature logs:

```logql
{source="dedicated", host="kayra", env="feature"}
```

Production logs:

```logql
{source="dedicated", env="prod"}
```

Errors:

```logql
{source="dedicated", env="prod"} |~ "(?i)(error|exception|failed|failure|fatal|panic|timeout|caused by)"
```
