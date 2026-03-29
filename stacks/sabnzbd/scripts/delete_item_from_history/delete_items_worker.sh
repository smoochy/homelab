#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DELETE_SCRIPT="${SCRIPT_DIR}/delete_item.sh"
QUEUE_FILE="${SCRIPT_DIR}/delete_item.queue"
TMP_FILE="${QUEUE_FILE}.tmp"
LOCK_DIR="${QUEUE_FILE}.lock"

read_delete_script_value() {
  local key="$1"
  awk -F '=' -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]*"/, "", value)
      gsub(/"[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$DELETE_SCRIPT"
}

ensure_queue_file() {
  mkdir -p "$(dirname "$QUEUE_FILE")"
  touch "$QUEUE_FILE"
}

resolve_history_identifier() {
  local identifier="$1"
  local api_url="$2"
  local api_key="$3"
  local insecure_flag="$4"
  local curl_opts=()

  if [[ "$identifier" == SABnzbd_nzo_* ]]; then
    printf '%s\n' "$identifier"
    return 0
  fi

  [[ "$insecure_flag" == "1" ]] && curl_opts+=( -k )

  docker exec "$SAB_CONTAINER_NAME" curl "${curl_opts[@]}" -fsS -G "$api_url" \
    --data-urlencode "mode=history" \
    --data-urlencode "limit=50" \
    --data-urlencode "output=json" \
    --data-urlencode "apikey=$api_key" | \
    sed 's/},{/},\n{/g' | \
    grep -F "\"name\":\"$identifier\"" | \
    sed -n 's/.*"nzo_id":"\([^"]*\)".*/\1/p' | head -n 1
}

[[ -f "$DELETE_SCRIPT" ]] || {
  echo "[WARN] delete_items_worker: missing delete script at '$DELETE_SCRIPT'"
  exit 0
}

SAB_CONTAINER_NAME="$(read_delete_script_value SAB_CONTAINER_NAME)"
[[ -n "$SAB_CONTAINER_NAME" ]] || {
  echo "[WARN] delete_items_worker: SAB container name is not configured in '$DELETE_SCRIPT'"
  exit 0
}

ensure_queue_file
mkdir "$LOCK_DIR" 2>/dev/null || {
  echo "[INFO] delete_items_worker: already running"
  exit 0
}
trap 'rmdir "$LOCK_DIR"' EXIT

processed=0
deleted=0
skipped=0
requeued=0

echo "[INFO] delete_items_worker: start container='$SAB_CONTAINER_NAME' queue='$QUEUE_FILE'"

: > "$TMP_FILE"

while IFS=$'\t' read -r col1 col2 col3 col4 col5; do
  [[ -n "${col1:-}" ]] || continue

  if [[ -n "${col5:-}" && "$col1" =~ ^[0-9]+$ ]]; then
    identifier="$col2"
    api_url="$col3"
    api_key="$col4"
    insecure_flag="$col5"
  else
    identifier="$col1"
    api_url="$col2"
    api_key="$col3"
    insecure_flag="$col4"
  fi

  if [[ -z "$identifier" || -z "$api_url" || -z "$api_key" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$api_url" != http://* && "$api_url" != https://* ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  processed=$((processed + 1))
  nzo_id="$(resolve_history_identifier "$identifier" "$api_url" "$api_key" "$insecure_flag" || true)"
  if [[ -z "$nzo_id" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  curl_opts=()
  [[ "$insecure_flag" == "1" ]] && curl_opts+=( -k )

  if docker exec "$SAB_CONTAINER_NAME" curl "${curl_opts[@]}" -fsS -G "$api_url" \
    --data-urlencode "mode=history" \
    --data-urlencode "name=delete" \
    --data-urlencode "archive=0" \
    --data-urlencode "value=$nzo_id" \
    --data-urlencode "apikey=$api_key" \
    --data-urlencode "output=json" >/dev/null; then
    deleted=$((deleted + 1))
    echo "[INFO] delete_items_worker: deleted identifier='$identifier' nzo_id='$nzo_id'"
  else
    requeued=$((requeued + 1))
    printf '%s\t%s\t%s\t%s\n' \
      "$identifier" "$api_url" "$api_key" "$insecure_flag" >> "$TMP_FILE"
    echo "[WARN] delete_items_worker: requeued identifier='$identifier' nzo_id='$nzo_id'"
  fi
done < "$QUEUE_FILE"

mv "$TMP_FILE" "$QUEUE_FILE"

echo "[INFO] delete_items_worker: end processed=$processed deleted=$deleted skipped=$skipped requeued=$requeued"
exit 0
