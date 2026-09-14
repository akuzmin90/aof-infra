#!/usr/bin/env bash
# Explicit tokenFile config avoids kubectl's default-config/in-cluster detection
# changing when command-line overrides such as --request-timeout are supplied.
configure_cluster() {
  local directory=$1
  local account=/var/run/secrets/kubernetes.io/serviceaccount
  if [[ -n "${KUBERNETES_SERVICE_HOST:-}" && -r "$account/token" ]]; then
    local host=$KUBERNETES_SERVICE_HOST
    [[ "$host" != *:* ]] || host="[$host]"
    export KUBECONFIG="$directory/kubeconfig"
    (umask 077; cat > "$KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ci
  cluster:
    server: https://$host:${KUBERNETES_SERVICE_PORT_HTTPS:-443}
    certificate-authority: $account/ca.crt
users:
- name: ci
  user:
    tokenFile: $account/token
contexts:
- name: ci
  context:
    cluster: ci
    user: ci
current-context: ci
EOF
    )
  fi
}
