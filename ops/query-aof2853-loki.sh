#!/usr/bin/env bash

set -euo pipefail

KUBE_CONTEXT="admin@aof-k8s"
LOOKBACK_HOURS="${1:-8}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/loki-aof2853-last${LOOKBACK_HOURS}h.json"

LOG_QUERY='{source="dedicated",host="prod",env="prod"} |~ "(?i)(artifact|артефакт|upgrade|улучшен|mithril|измр)"'
ENCODED_QUERY="$(jq -rn --arg query "${LOG_QUERY}" '$query | @uri')"
START_NS="$(date -u -d "${LOOKBACK_HOURS} hours ago" +%s%N)"
END_NS="$(date -u +%s%N)"
LOKI_PATH="/api/v1/namespaces/observability/services/http:loki:3100/proxy/loki/api/v1/query_range?query=${ENCODED_QUERY}&start=${START_NS}&end=${END_NS}&limit=5000&direction=forward"

kubectl --context "${KUBE_CONTEXT}" --request-timeout=10m get --raw "${LOKI_PATH}" > "${OUTPUT_FILE}"

if [[ "$(jq -r '.status' "${OUTPUT_FILE}")" != "success" ]]; then
    echo "Loki returned an unsuccessful response: ${OUTPUT_FILE}" >&2
    exit 1
fi

ENTRY_COUNT="$(jq '[.data.result[].values[]] | length' "${OUTPUT_FILE}")"

echo "Saved ${ENTRY_COUNT} matching log entries to:"
echo "${OUTPUT_FILE}"

if [[ "${ENTRY_COUNT}" -ge 5000 ]]; then
    echo "WARNING: Loki returned the 5000-entry limit; the result needs pagination." >&2
fi
