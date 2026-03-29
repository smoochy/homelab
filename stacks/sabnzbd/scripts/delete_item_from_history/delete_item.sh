#!/usr/bin/env bash
set -euo pipefail

DELETE_CATEGORIES="mhh" # Comma-separated list of categories to delete
SAB_CONTAINER_NAME="sabnzbd"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/config/sabnzbd.ini"
QUEUE_FILE="${SCRIPT_DIR}/delete_item.queue"

NZO_ID="${SAB_NZO_ID:-}"
JOB_NAME="${3:-}"
CAT="${5:-${SAB_CAT:-}}"
STATUS="${7:-${SAB_STATUS:-}}"
IDENTIFIER="${NZO_ID:-$JOB_NAME}"

read_misc_value() {
  local key="$1"
  awk -F ' = ' -v key="$key" '
    /^\[misc\]$/ { in_misc=1; next }
    /^\[/ && in_misc { exit }
    in_misc && $1 == key { print substr($0, index($0, " = ") + 3); exit }
  ' "$CONFIG_FILE"
}

ensure_queue_file() {
  mkdir -p "$(dirname "$QUEUE_FILE")"
  touch "$QUEUE_FILE"
}

[[ "$STATUS" == "0" ]] || exit 0
[[ -n "$IDENTIFIER" ]] || exit 0

category_match=1
IFS=',' read -r -a configured_categories <<< "$DELETE_CATEGORIES"
for configured_category in "${configured_categories[@]}"; do
  configured_category="${configured_category#"${configured_category%%[![:space:]]*}"}"
  configured_category="${configured_category%"${configured_category##*[![:space:]]}"}"
  [[ -n "$configured_category" ]] || continue
  if [[ "$CAT" == "$configured_category" ]]; then
    category_match=0
    break
  fi
done

[[ "$category_match" -eq 0 ]] || exit 0
[[ -f "$CONFIG_FILE" ]] || exit 0

ENABLE_HTTPS="$(read_misc_value enable_https)"
PORT="$(read_misc_value port)"
HTTPS_PORT="$(read_misc_value https_port)"
URL_BASE="$(read_misc_value url_base)"
API_KEY="$(read_misc_value api_key)"

[[ -n "$API_KEY" ]] || exit 0

URL_BASE="${URL_BASE%/}"
if [[ "$ENABLE_HTTPS" == "1" ]]; then
  API_URL="https://127.0.0.1:${HTTPS_PORT}${URL_BASE}/api"
  INSECURE_FLAG=1
else
  API_URL="http://127.0.0.1:${PORT}${URL_BASE}/api"
  INSECURE_FLAG=0
fi

ensure_queue_file
printf '%s\t%s\t%s\t%s\n' \
  "$IDENTIFIER" \
  "$API_URL" \
  "$API_KEY" \
  "$INSECURE_FLAG" >> "$QUEUE_FILE"

exit 0
