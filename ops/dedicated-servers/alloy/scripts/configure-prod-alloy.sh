#!/usr/bin/env bash
set -euo pipefail

# Configures Grafana Alloy on production dedicated server and starts it.
#
# Required:
#   DEDICATED_LOGS_PASSWORD
#
# Optional:
#   HOST_LABEL          default: prod
#   ENV_LABEL           default: prod
#   TOMCAT_LOG_PATH     default: /opt/apache-tomcat-9.0.21/logs/catalina.out
#   POSTGRES_LOG_GLOB   default: /var/log/postgresql/*.log

: "${DEDICATED_LOGS_PASSWORD:?Missing DEDICATED_LOGS_PASSWORD}"

HOST_LABEL="${HOST_LABEL:-prod}"
ENV_LABEL="${ENV_LABEL:-prod}"
TOMCAT_LOG_PATH="${TOMCAT_LOG_PATH:-/opt/apache-tomcat-9.0.21/logs/catalina.out}"
POSTGRES_LOG_GLOB="${POSTGRES_LOG_GLOB:-/var/log/postgresql/*.log}"

if ! command -v alloy >/dev/null 2>&1; then
  echo "Alloy is not installed. Run install-alloy-ubuntu.sh first." >&2
  exit 1
fi

sudo install -d -m 0755 /etc/alloy

tmp_config="$(mktemp)"
cat > "$tmp_config" <<EOF
loki.source.file "tomcat" {
  targets = [
    {
      __path__ = "$TOMCAT_LOG_PATH",
      source   = "dedicated",
      host     = "$HOST_LABEL",
      env      = "$ENV_LABEL",
      service  = "tomcat",
    },
  ]

  forward_to = [loki.process.java_multiline.receiver]
}

loki.process "java_multiline" {
  stage.multiline {
    firstline     = "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"
    max_wait_time = "3s"
  }

  forward_to = [loki.write.cluster.receiver]
}

loki.source.file "postgres" {
  targets = [
    {
      __path__ = "$POSTGRES_LOG_GLOB",
      source   = "dedicated",
      host     = "$HOST_LABEL",
      env      = "$ENV_LABEL",
      service  = "postgres",
    },
  ]

  forward_to = [loki.write.cluster.receiver]

  file_match {
    enabled     = true
    sync_period = "30s"
  }
}

loki.write "cluster" {
  endpoint {
    url = "https://grafana.k8s.zazer.fun/loki/api/v1/push"

    basic_auth {
      username = "alloy"
      password = "$DEDICATED_LOGS_PASSWORD"
    }
  }
}
EOF

sudo install -m 0600 "$tmp_config" /etc/alloy/config.alloy
rm -f "$tmp_config"

sudo usermod -aG adm alloy || true

sudo systemctl enable alloy
sudo systemctl restart alloy
sudo systemctl status alloy --no-pager
