#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 022
: "${WORKSPACE:?}" "${NAMESPACE:?}" "${RELEASE_NAME:?}" "${DEPLOY_TIMEOUT:?}" "${DEPLOY_SECONDS:?}" "${BUILD_ID:?}"
script_dir=$(cd "$(dirname "$0")" && pwd)
logs="$WORKSPACE/ci-logs"
mkdir -p "$logs"
tmp=$(mktemp -d)
source "$script_dir/cluster.sh"
configure_cluster "$tmp"
pid=''
started=$SECONDS
interval=${STATUS_INTERVAL:-15}
diagnostics_done=false
stop_helm() {
  if [[ -n "$pid" ]]; then
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=''
  fi
}
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  stop_helm
  if (( rc != 0 )); then
    echo "[Deploy] FAILED after $((SECONDS-started))s. $NAMESPACE / $RELEASE_NAME"
    [[ ! -f "$logs/helm.log" ]] || tail -n 60 "$logs/helm.log"
    if [[ "$diagnostics_done" != true ]]; then
      timeout -k 5s 110s bash "$script_dir/diagnostics.sh" || echo '[Diagnostics] Incomplete or exceeded time budget.'
    fi
  fi
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "[Deploy] Cancelled or interrupted; stopping Helm. Inspect release history before retrying."; exit 130' INT TERM
k() { kubectl --request-timeout=8s -n "$NAMESPACE" "$@"; }
# Retry only idempotent preflight reads. Never replay helm upgrade or migrations.
read_retry() {
  local n
  for n in 1 2 3; do
    if "$@" 2> "$tmp/preflight-error"; then return 0; fi
    echo "[Deploy] Preflight read failed ($n/3): $(tail -n 1 "$tmp/preflight-error")" >&2
    sleep 2
  done
  return 1
}
read_retry kubectl --request-timeout=8s get namespace "$NAMESPACE" > /dev/null
read_retry k get secret "$DB_CLUSTER-app" > /dev/null
if timeout 15 helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json > "$tmp/release.json" 2> "$tmp/status-error"; then
  release_status=$(jq -r '.info.status' "$tmp/release.json")
  if [[ "$release_status" == pending-* ]]; then
    echo "[Deploy] Release is $release_status. Review the interrupted operation before retrying; no automatic unlock or rollback."
    exit 1
  fi
elif ! grep -qi 'release: not found' "$tmp/status-error"; then
  cat "$tmp/status-error" >&2
  exit 1
fi
IMAGE_DIGEST=$(cat "$logs/image-digest.txt")
[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo '[Deploy] Missing/invalid pushed digest.'; exit 1; }
export IMAGE_DIGEST
mkdir "$tmp/chart"
for file in Chart.yaml values.yaml values.schema.json templates .helmignore; do
  cp -RL "${CHART_SOURCE:-/charts/aof-back}/$file" "$tmp/chart/$file"
done
export DB_SECRET="$DB_CLUSTER-app"
bash "$script_dir/values.sh" > "$tmp/values.yaml"
echo "[Deploy] Validating chart; target $NAMESPACE, image $IMAGE_TAG."
if ! helm lint "$tmp/chart" -f "$tmp/values.yaml" > "$logs/chart-validation.log" 2>&1; then cat "$logs/chart-validation.log"; exit 1; fi
# Rendered manifests are private temporary data, never archived.
if ! helm template "$RELEASE_NAME" "$tmp/chart" -n "$NAMESPACE" -f "$tmp/values.yaml" > "$tmp/rendered.yaml" 2>> "$logs/chart-validation.log"; then cat "$logs/chart-validation.log"; exit 1; fi
echo "[Deploy] Starting rollout — timeout $DEPLOY_TIMEOUT."
setsid helm upgrade --install "$RELEASE_NAME" "$tmp/chart" --namespace "$NAMESPACE" \
  -f "$tmp/values.yaml" --wait --timeout "$DEPLOY_TIMEOUT" > "$logs/helm.log" 2>&1 &
pid=$!
declare -A pull_since=()
last_event=''
api_failures=0
last_progress=''
last_progress_at=0
snapshot() {
  k get deployment "$RELEASE_NAME" -o json > "$tmp/deployment.json" &&
  k get replicasets -l "app.kubernetes.io/instance=$RELEASE_NAME" -o json > "$tmp/rs.json" &&
  k get pods -l "app.kubernetes.io/instance=$RELEASE_NAME" -o json > "$tmp/pods.json" &&
  jq -n --arg build "$BUILD_ID" --slurpfile deploy "$tmp/deployment.json" --slurpfile rs "$tmp/rs.json" --slurpfile pods "$tmp/pods.json" -f "$script_dir/rollout.jq" > "$tmp/progress.json"
}
check_progress() {
  if ! snapshot 2> "$tmp/api-error"; then
    api_failures=$((api_failures+1))
    echo "[Deploy +$((SECONDS-started))s] Unable to read rollout status ($api_failures/3)."
    if (( api_failures >= 3 )); then cat "$tmp/api-error" >&2; return 1; fi
    return 0
  fi
  api_failures=0
  cp "$tmp/progress.json" "$logs/rollout-status.json"
  local progress
  progress=$(jq -r '
    if .observed != true then "Waiting for the new rollout to be observed"
    else ([.pods[] | (.containers | map(.restarts) | add // 0) as $restarts |
      (if .ready then "Ready" else .phase + "; not ready" end) + "; " + ($restarts|tostring) + " restarts" +
      ([.containers[].reason | select(. != "")] | unique | if length > 0 then "; " + join(", ") else "" end)] |
      if length == 0 then "Waiting for new pods" else join(" | ") end) end
  ' "$tmp/progress.json")
  if [[ "$progress" != "$last_progress" ]] || (( SECONDS-last_progress_at >= 30 )); then
    echo "[Deploy +$((SECONDS-started))s] $progress"
    last_progress=$progress
    last_progress_at=$SECONDS
  fi
  # Do not judge pods until the controller has observed this build's generation.
  [[ $(jq -r '.observed' "$tmp/progress.json") == true ]] || return 0
  local failure
  failure=$(jq -r '[.pods[] | .name as $pod |
    if .phase == "Failed" then $pod+": pod failed" else
    .containers[] | .reason as $reason | select(.restarts >= 3 or (["CrashLoopBackOff","InvalidImageName","CreateContainerConfigError","OOMKilled"] | index($reason)) != null) |
    $pod+"/"+.name+": "+.reason+" (restarts="+(.restarts|tostring)+")" end] | .[0] // ""' "$tmp/progress.json")
  if [[ -n "$failure" ]]; then echo "[Deploy] Early failure: $failure"; return 1; fi
  local key reason
  declare -A active_pull=()
  while IFS=$'\t' read -r key reason; do
    [[ -n "$key" ]] || continue
    active_pull[$key]=1
    [[ -v pull_since[$key] ]] || pull_since[$key]=$SECONDS
    if (( SECONDS - pull_since[$key] >= ${PULL_FAILURE_GRACE:-60} )); then echo "[Deploy] Early failure: $key remains $reason for at least 60s."; return 1; fi
  done < <(jq -r '.pods[] | .uid as $uid | .containers[] | select(.reason=="ErrImagePull" or .reason=="ImagePullBackOff") | [$uid+"/"+.name,.reason] | @tsv' "$tmp/progress.json")
  for key in "${!pull_since[@]}"; do [[ -v active_pull[$key] ]] || unset 'pull_since[$key]'; done
  # Events are scoped to this rollout's pod UIDs and emitted only when changed.
  if k get events -o json > "$tmp/events.json" 2>/dev/null; then
    event=$(jq -r --slurpfile progress "$tmp/progress.json" '[.items[] | select(.involvedObject.uid as $uid | [$progress[0].pods[].uid] | index($uid))] | sort_by(.lastTimestamp // .metadata.creationTimestamp) | last | if . then .reason+": "+.message else "" end' "$tmp/events.json")
    if [[ -n "$event" && "$event" != "$last_event" ]]; then echo "  Latest event: $event"; last_event=$event; fi
  fi
}
while kill -0 "$pid" 2>/dev/null; do
  if (( SECONDS-started >= DEPLOY_SECONDS+30 )); then echo '[Deploy] Deployment command exceeded its deadline.'; exit 1; fi
  check_progress || exit 1
  sleep "$interval"
done
status=0
wait "$pid" || status=$?
pid=''
if (( status != 0 )); then echo "[Deploy] Helm failed with exit $status."; exit "$status"; fi
snapshot || { echo '[Deploy] Helm finished, but final rollout verification failed.'; exit 1; }
cp "$tmp/progress.json" "$logs/rollout-status.json"
[[ $(jq -r '.ready' "$tmp/progress.json") == true ]] || { echo '[Deploy] Helm returned success but the new revision is not ready.'; exit 1; }
echo "[Deploy] SUCCESS — Ready — $(jq -r '(.available|tostring)+"/"+(.desired|tostring)' "$tmp/progress.json") pods; $((SECONDS-started))s."
