#!/bin/bash
set -eu
set +x
: "${FAILED_POD:?}"
sa=/var/run/secrets/kubernetes.io/serviceaccount
config=$(mktemp)
trap 'rm -f "$config"' EXIT
cat > "$config" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: aof
  cluster:
    server: https://$KUBERNETES_SERVICE_HOST:${KUBERNETES_SERVICE_PORT_HTTPS:-443}
    certificate-authority: $sa/ca.crt
users:
- name: agent
  user:
    tokenFile: $sa/token
contexts:
- name: aof
  context:
    cluster: aof
    user: agent
    namespace: jenkins
current-context: aof
EOF
export KUBECONFIG="$config"
status=$(kubectl --request-timeout=8s get pod "$FAILED_POD" -o 'jsonpath={.status.reason}{"\n"}{.status.message}{"\n"}{range .status.containerStatuses[*]}{.state.terminated.reason}{"\n"}{.lastState.terminated.reason}{"\n"}{end}' 2>/dev/null) || status=''
events=$(kubectl --request-timeout=8s get events --field-selector "involvedObject.name=$FAILED_POD" -o 'jsonpath={range .items[*]}{.reason}{": "}{.message}{"\n"}{end}' 2>/dev/null) || events=''
if printf '%s\n%s\n' "$status" "$events" | grep -Eiq 'OOMKilled|out of memory|low on resource|MemoryPressure|DiskPressure|Insufficient (memory|cpu)|ephemeral-storage.*(exceed|limit)'; then
  echo '[Agent] Kubernetes confirms a resource failure; emergency CI retry is permitted.'
  exit 0
fi
echo '[Agent] No Kubernetes resource failure confirmed; emergency CI will not be started.'
exit 1
