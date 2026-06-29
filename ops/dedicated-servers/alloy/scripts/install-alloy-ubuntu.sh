#!/usr/bin/env bash
set -euo pipefail

# Installs Grafana Alloy on Ubuntu/Debian.
#
# Preferred for restricted networks:
#   ALLOY_DEB_PATH=/tmp/alloy-1.17.0-1.amd64.deb ./install-alloy-ubuntu.sh
#
# Alternative:
#   ALLOY_DEB_URL=https://.../alloy-x.y.z-1.amd64.deb ./install-alloy-ubuntu.sh

if command -v alloy >/dev/null 2>&1; then
  alloy --version
  exit 0
fi

if [ -n "${ALLOY_DEB_PATH:-}" ]; then
  sudo dpkg -i "$ALLOY_DEB_PATH"
elif [ -n "${ALLOY_DEB_URL:-}" ]; then
  tmp_deb="/tmp/alloy.deb"
  wget -O "$tmp_deb" "$ALLOY_DEB_URL"
  sudo dpkg -i "$tmp_deb"
else
  sudo mkdir -p /etc/apt/keyrings
  wget -O /tmp/grafana.asc https://apt.grafana.com/gpg-full.key
  sudo mv /tmp/grafana.asc /etc/apt/keyrings/grafana.asc
  echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y alloy
fi

alloy --version

