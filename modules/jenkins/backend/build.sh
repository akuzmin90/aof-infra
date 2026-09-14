#!/busybox/sh
# The build context and log directory are deliberately separate: Kaniko replaces its rootfs.
set -eu
set +x
umask 022
: "${WORKSPACE:?}" "${IMAGE_REPOSITORY:?}" "${IMAGE_TAG:?}" "${REGISTRY_SERVER:?}" "${REGISTRY_USERNAME:?}" "${REGISTRY_PASSWORD:?}"
logs="$WORKSPACE/ci-logs"
config_dir=${DOCKER_CONFIG_DIR:-/kaniko/.docker}
mkdir -p "$logs" "$config_dir"
export PATH="/busybox:$PATH"
pid=''
cleanup() {
  trap - EXIT INT TERM
  if [ -n "$pid" ]; then
    kill -TERM "-$pid" 2>/dev/null || true
    sleep 2
    kill -KILL "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$config_dir/config.json"
}
trap cleanup EXIT
trap 'echo "[Build] Cancelled; stopping image build."; exit 130' INT TERM
AUTH=$(printf '%s:%s' "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" | base64 | tr -d '\n')
(umask 077; printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REGISTRY_SERVER" "$AUTH" > "$config_dir/config.json")
unset AUTH REGISTRY_PASSWORD REGISTRY_USERNAME
rm -f "$logs/image-digest.txt"
printf '[Build] Building %s:%s (Java 17; tests skipped by the Dockerfile).\n' "$IMAGE_REPOSITORY" "$IMAGE_TAG"
start=$(date +%s)
: > "$logs/image-build.log"
setsid "${KANIKO_EXECUTOR:-/kaniko/executor}" --context "$WORKSPACE/source" --dockerfile "$WORKSPACE/source/Dockerfile" \
  --destination "$IMAGE_REPOSITORY:$IMAGE_TAG" --build-arg JAVA_VERSION=17 --cache=true \
  --digest-file "$logs/image-digest.txt" --push-retry=2 --image-download-retry=2 --log-format=text --log-timestamp=true \
  > "$logs/image-build.log" 2>&1 &
pid=$!
line=0
heartbeat=$start
emit_progress() {
  # Always retain the complete log; only selected milestones are copied to the console.
  count=$(wc -l < "$logs/image-build.log")
  if [ "$count" -gt "$line" ]; then
    sed -n "$((line + 1)),${count}p" "$logs/image-build.log" | awk '
      /\[ERROR\]|\[WARNING\]|level=(error|warning)|deprecated API|unchecked or unsafe|Tests are skipped|BUILD SUCCESS|BUILD FAILURE|Total time:|Compiling [0-9]+ source|Packaging webapp/ {print "[Build] " $0; next}
      /Building stage/ {print "[Build] Preparing container stage."; next}
      /Pushing image to/ && !/\/cache/ {print "[Build] Pushing application image."}
    '
    line=$count
  fi
}
while kill -0 "$pid" 2>/dev/null; do
  emit_progress
  now=$(date +%s)
  if [ "$((now-heartbeat))" -ge 60 ]; then echo "[Build +$((now-start))s] Still building/publishing; full output is in ci-logs/image-build.log."; heartbeat=$now; fi
  sleep 3
done
status=0
wait "$pid" || status=$?
pid=''
emit_progress
if [ "$status" -ne 0 ]; then
  echo "[Build] FAILED (exit $status). Last 100 lines:"
  tail -n 100 "$logs/image-build.log"
  exit "$status"
fi
digest=$(cat "$logs/image-digest.txt")
if ! printf '%s\n' "$digest" | grep -Eq '^sha256:[a-f0-9]{64}$'; then echo '[Build] Invalid or missing image digest; refusing deployment.'; exit 1; fi
printf '[Build] Image published — %ss (digest saved in artifacts).\n' "$(($(date +%s)-start))"
