#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="${SCRIPT_DIR}/appdata_backup_kuma_helper.sh"

HOOK_ACTION="${1:-pre-run}"
DESTINATION="${2:-}"

if [[ ! -x "$HELPER_SCRIPT" ]]; then
  printf '%s backup-kuma: helper is missing or not executable: %s\n' "$(date '+%F %T')" "$HELPER_SCRIPT" >&2
  exit 0
fi

printf '%s backup-kuma: pre hook invoked action=%s destination=%s\n' \
  "$(date '+%F %T')" \
  "$HOOK_ACTION" \
  "${DESTINATION:-n/a}"

if ! "$HELPER_SCRIPT" start; then
  printf '%s backup-kuma: failed to enable Uptime Kuma maintenance, continuing backup\n' "$(date '+%F %T')" >&2
fi

exit 0
