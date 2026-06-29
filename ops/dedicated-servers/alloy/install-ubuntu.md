# Install Alloy On Ubuntu/Debian Dedicated Server

This runbook installs Grafana Alloy and configures it to push logs to the Kubernetes Loki stack.

## 1. Install Package

If Grafana APT repository is available:

```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y alloy
```

If the Grafana APT repository is blocked, download the `.deb` release from GitHub on a machine that can access it, copy it to the server, then install:

```bash
sudo dpkg -i alloy-*.deb
alloy --version
```

## 2. Install Config

Copy the selected config to:

```text
/etc/alloy/config.alloy
```

Use:

- `kayra/config.alloy` for Kayra-like mixed host and Docker logs;
- `templates/host-only.config.alloy` for production-style host logs without Docker.

Replace placeholders:

```text
__HOST__
__ENV__
__DEDICATED_LOGS_PASSWORD__
```

## 3. Permissions

Alloy must be able to read log files.

For PostgreSQL logs:

```bash
sudo usermod -aG adm alloy
```

For Docker logs:

```bash
sudo usermod -aG docker alloy
```

Then restart Alloy:

```bash
sudo systemctl restart alloy
```

## 4. Start And Check

```bash
sudo systemctl enable alloy
sudo systemctl restart alloy
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy -n 100 --no-pager
```

## 5. Verify In Grafana

Open:

```text
https://grafana.k8s.zazer.fun
```

Run a query:

```logql
{source="dedicated", host="__HOST__"}
```

For production:

```logql
{source="dedicated", env="prod"}
```

## 6. Common Problems

401 Unauthorized:

- wrong basic auth username or password;
- password was not replaced in `/etc/alloy/config.alloy`.

No logs:

- wrong file path;
- Alloy user cannot read the log file;
- service has not written new lines since Alloy started;
- firewall blocks outbound HTTPS to `grafana.k8s.zazer.fun`.

Docker logs missing:

- Alloy user is not in `docker` group;
- Docker socket path is not `/var/run/docker.sock`;
- container names do not match the relabel regex.

