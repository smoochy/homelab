#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="${SCRIPT_DIR}/appdata_backup_kuma_helper.sh"

HOOK_ACTION="${1:-post-run}"
DESTINATION="${2:-}"
BACKUP_SUCCESS="${3:-unknown}"

if [[ ! -x "$HELPER_SCRIPT" ]]; then
  printf '%s backup-kuma: helper is missing or not executable: %s\n' "$(date '+%F %T')" "$HELPER_SCRIPT" >&2
  exit 0
fi

printf '%s backup-kuma: post hook invoked action=%s destination=%s success=%s\n' \
  "$(date '+%F %T')" \
  "$HOOK_ACTION" \
  "${DESTINATION:-n/a}" \
  "$BACKUP_SUCCESS"

if ! "$HELPER_SCRIPT" stop; then
  printf '%s backup-kuma: failed to disable Uptime Kuma maintenance, continuing backup cleanup\n' "$(date '+%F %T')" >&2
fi

exit 0
