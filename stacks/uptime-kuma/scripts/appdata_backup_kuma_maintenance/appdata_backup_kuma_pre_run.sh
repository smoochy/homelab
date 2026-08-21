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

# Mute the stack-health poller for the same window. The backup stops containers
# on purpose, which is indistinguishable from the outage the poller exists to
# report, so it would page for every stack the backup touches. The marker is
# removed again by the post-run hook and expires on its own if that never runs.
STACK_HEALTH_PAUSE_FILE="${STACK_HEALTH_PAUSE_FILE:-/mnt/user/appdata/stack-health/paused}"
if ! mkdir -p "$(dirname -- "$STACK_HEALTH_PAUSE_FILE")" 2>/dev/null || ! : > "$STACK_HEALTH_PAUSE_FILE"; then
  printf '%s backup-kuma: could not pause stack-health, continuing backup\n' "$(date '+%F %T')" >&2
fi

if ! "$HELPER_SCRIPT" start; then
  printf '%s backup-kuma: failed to enable Uptime Kuma maintenance, continuing backup\n' "$(date '+%F %T')" >&2
fi

exit 0
