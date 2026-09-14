#!/usr/bin/env bash
set +x
set -u
umask 022
diag_tmp=$(mktemp -d)
trap 'rm -rf "$diag_tmp"' EXIT
source "$(dirname "$0")/cluster.sh"
configure_cluster "$diag_tmp"
mkdir -p "$WORKSPACE/ci-logs"
selector="app.kubernetes.io/instance=$RELEASE_NAME"
k() { kubectl --request-timeout=8s -n "$NAMESPACE" "$@"; }
{
  echo '[Diagnostics] Deployment and pods'
  k get deployments,replicasets,pods -l "$selector" -o wide || true
  echo '[Diagnostics] Pod conditions and container exit reasons'
  # JSON status omits environment variables and mounted Secret contents.
  k get pods -l "$selector" -o json | jq '.items[] | {name:.metadata.name, status:.status}' || true
  echo '[Diagnostics] Recent namespace events'
  k get events --sort-by=.metadata.creationTimestamp | tail -n 60 || true
  for pod in $(k get pods -l "$selector" -o name); do
    echo "[Diagnostics] $pod current logs"
    k logs "$pod" --all-containers=true --prefix=true --timestamps=true --tail=200 --pod-running-timeout=5s || true
    echo "[Diagnostics] $pod previous logs"
    k logs "$pod" --all-containers=true --prefix=true --timestamps=true --tail=200 --previous --pod-running-timeout=5s || true
  done
  echo '[Diagnostics] Helm release history (pending operations require review, never automatic metadata deletion)'
  timeout 12 helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 5 || true
} 2>&1 | tee "$WORKSPACE/ci-logs/deployment-diagnostics.log"
