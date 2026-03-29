#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV_FILE="${CONFIG_ENV_FILE:-${SCRIPT_DIR}/.env}"

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

load_env_file "$CONFIG_ENV_FILE"

# User settings: override these via .env in the same directory.
APPDATA_ROOT="${APPDATA_ROOT:-/mnt/user/appdata}"            # Base appdata directory on the host.
SAB_APPDATA_DIR="${SAB_APPDATA_DIR:-/mnt/user/appdata/sabnzbd}" # SABnzbd appdata directory containing sabnzbd.ini.
SAB_HOST="${SAB_HOST:-127.0.0.1}"                        # Hostname or IP where the SABnzbd API is reachable.
SAB_PORT="${SAB_PORT:-8082}"                             # Host port that exposes the SABnzbd web/API interface.
SAB_URL_BASE="${SAB_URL_BASE:-/sabnzbd}"                     # SABnzbd URL base path.
AVERAGE_WINDOW_MINUTES="${AVERAGE_WINDOW_MINUTES:-2}"                  # Average download speed over this many minutes.
SPEED_THRESHOLD_MBPS="${SPEED_THRESHOLD_MBPS:-10}"                   # Restart threshold in MB/s for the sampled average speed.
COOLDOWN_MINUTES="${COOLDOWN_MINUTES:-1}"                       # Minimum minutes between two recovery actions.
LOG_RESET_DAYS="${LOG_RESET_DAYS:-1}"                          # Clear the logfile after this many days. Set to 0 to disable.
RECOVERY_METHOD="${RECOVERY_METHOD:-komodo_stack}"              # Recovery mode: komodo_stack, komodo_split_stacks, komodo_procedure, or docker.
KOMODO_STACK_NAME="${KOMODO_STACK_NAME:-sabnzbd}"                 # Komodo stack name when gluetun and SABnzbd are in one stack.
GLUETUN_STACK_NAME="${GLUETUN_STACK_NAME:-gluetun}"                # Komodo gluetun stack name for split-stack recovery.
SAB_STACK_NAME="${SAB_STACK_NAME:-sabnzbd}"                    # Komodo sabnzbd stack name for split-stack recovery.
KOMODO_PROCEDURE_NAME="${KOMODO_PROCEDURE_NAME:-}"                    # Optional Komodo procedure name when using komodo_procedure.
KOMODO_CORE_NAME="${KOMODO_CORE_NAME:-komodo-core}"              # Komodo core container name used for km execute.
KOMODO_CLI_KEY="${KOMODO_CLI_KEY:-}" # Komodo CLI key used for authenticated km execute calls.
KOMODO_CLI_SECRET="${KOMODO_CLI_SECRET:-}" # Komodo CLI secret used for authenticated km execute calls.
ENABLE_RECOVERY="${ENABLE_RECOVERY:-1}"                         # Set to 0 for dry-run mode without restart actions.
VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-1}"                          # Set to 1 to write to the logfile and print to stdout; 0 writes only to the logfile.
WAIT_FOR_SAB_SECONDS="${WAIT_FOR_SAB_SECONDS:-120}"                  # Max seconds to wait until SABnzbd responds again.
WAIT_AFTER_GLUETUN_SECONDS="${WAIT_AFTER_GLUETUN_SECONDS:-20}"             # Delay after gluetun restart in split recovery modes.
GLUETUN_CONTAINER="${GLUETUN_CONTAINER:-gluetun}"                 # Gluetun container name for docker recovery mode.
SAB_CONTAINER="${SAB_CONTAINER:-sabnzbd}"                     # SABnzbd container name for docker recovery mode.
ENABLE_KUMA_MAINTENANCE="${ENABLE_KUMA_MAINTENANCE:-1}"                 # Set to 1 to call the Kuma helper around recovery.
FORCE_LOW_SPEED_TEST="${FORCE_LOW_SPEED_TEST:-0}"                  # Optional test flag to force the low-speed branch.
FORCE_LOW_SPEED_MBPS="${FORCE_LOW_SPEED_MBPS:-0.50}"                # Forced MB/s value used when the low-speed test is active.
IGNORE_COOLDOWN_FOR_TEST="${IGNORE_COOLDOWN_FOR_TEST:-0}"            # Optional test flag to bypass cooldown during forced runs.

# Internal paths and compatibility aliases.
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/monitor_sab_speed.state}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/monitor_sab_speed.log}"
LOCK_DIR="${LOCK_DIR:-${SCRIPT_DIR}/monitor_sab_speed.lock}"
SAB_CONFIG="${SAB_CONFIG:-${SAB_APPDATA_DIR}/sabnzbd.ini}"
SAB_API_URL="${SAB_API_URL:-http://${SAB_HOST}:${SAB_PORT}${SAB_URL_BASE}/api}"
THRESHOLD_MBPS="${THRESHOLD_MBPS:-${SPEED_THRESHOLD_MBPS}}"
SAMPLE_WINDOW_SECONDS="${SAMPLE_WINDOW_SECONDS:-$((AVERAGE_WINDOW_MINUTES * 60))}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-$((COOLDOWN_MINUTES * 60))}"
LOG_RESET_SECONDS="${LOG_RESET_SECONDS:-$((LOG_RESET_DAYS * 86400))}"
KOMODO_CORE_CONTAINER="${KOMODO_CORE_CONTAINER:-${KOMODO_CORE_NAME}}"
KOMODO_STACK="${KOMODO_STACK:-${KOMODO_STACK_NAME}}"
GLUETUN_STACK="${GLUETUN_STACK:-${GLUETUN_STACK_NAME}}"
SAB_STACK="${SAB_STACK:-${SAB_STACK_NAME}}"
KOMODO_PROCEDURE="${KOMODO_PROCEDURE:-${KOMODO_PROCEDURE_NAME}}"
RESTART_ENABLED="${RESTART_ENABLED:-${ENABLE_RECOVERY}}"
KUMA_MAINTENANCE_ENABLED="${KUMA_MAINTENANCE_ENABLED:-${ENABLE_KUMA_MAINTENANCE}}"
KUMA_HELPER_PATH="${KUMA_HELPER_PATH:-${SCRIPT_DIR}/monitor_sab_speed_kuma.sh}"

PREV_TS=0
PREV_MBLEFT=""
PREV_NZO_ID=""
LAST_RESTART_TS=0

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

announce() {
  local message="$1"
  log "$message"
  if [[ "$VERBOSE_OUTPUT" == "1" ]]; then
    printf '%s %s\n' "$(date '+%F %T')" "$message"
  fi
}

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    announce "another run is already active, exiting"
    exit 0
  fi
  trap cleanup EXIT
}

reset_log_if_needed() {
  local now log_mtime log_age message

  (( LOG_RESET_SECONDS > 0 )) || return 0
  [[ -f "$LOG_FILE" ]] || return 0

  log_mtime="$(stat -c %Y "$LOG_FILE" 2>/dev/null || true)"
  [[ -n "$log_mtime" ]] || return 0

  now="$(date +%s)"
  log_age=$(( now - log_mtime ))
  (( log_age >= LOG_RESET_SECONDS )) || return 0

  : > "$LOG_FILE"
  message="logfile cleared after ${LOG_RESET_DAYS} day(s)"
  printf '%s %s\n' "$(date '+%F %T')" "$message" >> "$LOG_FILE"
  if [[ "$VERBOSE_OUTPUT" == "1" ]]; then
    printf '%s %s\n' "$(date '+%F %T')" "$message"
  fi
}

read_misc_value() {
  local key="$1"
  awk -F ' = ' -v key="$key" '
    /^\[misc\]$/ { in_misc=1; next }
    /^\[/ && in_misc { exit }
    in_misc && $1 == key { print substr($0, index($0, " = ") + 3); exit }
  ' "$SAB_CONFIG"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    announce "missing required command: $cmd"
    exit 1
  }
}

is_non_negative_decimal() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  # shellcheck disable=SC1090
  . "$STATE_FILE"
}

save_state() {
  local prev_ts="$1"
  local prev_mbleft="$2"
  local prev_nzo_id="$3"
  local last_restart_ts="$4"

  cat > "$STATE_FILE" <<STATEEOF
PREV_TS=${prev_ts}
PREV_MBLEFT="${prev_mbleft}"
PREV_NZO_ID="${prev_nzo_id}"
LAST_RESTART_TS=${last_restart_ts}
STATEEOF
}

save_baseline() {
  local prev_ts="$1"
  local prev_mbleft="$2"
  local prev_nzo_id="$3"
  local last_restart_ts="$4"

  save_state "$prev_ts" "$prev_mbleft" "$prev_nzo_id" "$last_restart_ts"
}

clear_baseline() {
  local last_restart_ts="$1"

  save_state 0 "" "" "$last_restart_ts"
}

fetch_queue() {
  local api_key="$1"
  curl -fsS -m 10 "${SAB_API_URL}?mode=queue&output=json&apikey=${api_key}"
}

wait_for_sab() {
  local api_key="$1"
  local deadline now

  deadline=$(( $(date +%s) + WAIT_FOR_SAB_SECONDS ))
  while :; do
    now=$(date +%s)
    if (( now >= deadline )); then
      announce "sab api still unreachable after ${WAIT_FOR_SAB_SECONDS}s"
      return 1
    fi

    if fetch_queue "$api_key" >/dev/null 2>&1; then
      announce "sab api reachable again"
      return 0
    fi

    sleep 5
  done
}

run_komodo_execution() {
  if [[ -z "$KOMODO_CLI_KEY" || -z "$KOMODO_CLI_SECRET" ]]; then
    announce "komodo: KOMODO_CLI_KEY and KOMODO_CLI_SECRET are required for km execute"
    return 1
  fi

  docker exec "$KOMODO_CORE_CONTAINER" km execute -y -k "$KOMODO_CLI_KEY" -s "$KOMODO_CLI_SECRET" "$@" 2>&1 \
    | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' >> "$LOG_FILE"
}

recover_via_docker() {
  announce "recovery: docker restart ${GLUETUN_CONTAINER}"
  docker restart "$GLUETUN_CONTAINER" >/dev/null
  sleep "$WAIT_AFTER_GLUETUN_SECONDS"

  announce "recovery: docker restart ${SAB_CONTAINER}"
  docker restart "$SAB_CONTAINER" >/dev/null
}

recover_via_komodo_stack() {
  announce "recovery: komodo restart-stack ${KOMODO_STACK}"
  run_komodo_execution restart-stack "$KOMODO_STACK"
}

recover_via_komodo_split_stacks() {
  announce "recovery: komodo restart-stack ${GLUETUN_STACK}"
  run_komodo_execution restart-stack "$GLUETUN_STACK"
  sleep "$WAIT_AFTER_GLUETUN_SECONDS"

  announce "recovery: komodo restart-stack ${SAB_STACK}"
  run_komodo_execution restart-stack "$SAB_STACK"
}

recover_via_komodo_procedure() {
  if [[ -z "$KOMODO_PROCEDURE" ]]; then
    announce "komodo procedure mode selected but KOMODO_PROCEDURE is empty"
    return 1
  fi

  announce "recovery: komodo run-procedure ${KOMODO_PROCEDURE}"
  run_komodo_execution run-procedure "$KOMODO_PROCEDURE"
}

kuma_is_enabled() {
  [[ "$KUMA_MAINTENANCE_ENABLED" == "1" ]]
}

run_kuma_helper() {
  local action="$1"
  shift

  if [[ ! -x "$KUMA_HELPER_PATH" ]]; then
    announce "kuma: helper script is not executable: ${KUMA_HELPER_PATH}"
    return 1
  fi

  LOG_FILE="$LOG_FILE" VERBOSE_OUTPUT="$VERBOSE_OUTPUT" "$KUMA_HELPER_PATH" "$action" "$@"
}

recover_stack() {
  local api_key="$1"
  local kuma_started_by_script=0
  local recovery_rc=0

  if [[ "$RESTART_ENABLED" != "1" ]]; then
    if [[ "$FORCE_LOW_SPEED_TEST" == "1" ]]; then
      if kuma_is_enabled; then
        announce "simulation: kuma helper would be started before recovery"
      fi
      announce "simulation: recovery would be suppressed because RESTART_ENABLED=0"
    elif kuma_is_enabled; then
      announce "kuma: helper not started because recovery is disabled"
    fi
    announce "dry-run: recovery suppressed for method=${RECOVERY_METHOD}"
    return 0
  fi

  require_command docker

  if kuma_is_enabled; then
    if run_kuma_helper start; then
      kuma_started_by_script=1
    else
      announce "kuma: continuing recovery without helper maintenance"
    fi
  fi

  case "$RECOVERY_METHOD" in
    docker)
      if recover_via_docker; then
        recovery_rc=0
      else
        recovery_rc=$?
      fi
      ;;
    komodo_stack)
      if recover_via_komodo_stack; then
        recovery_rc=0
      else
        recovery_rc=$?
      fi
      ;;
    komodo_split_stacks)
      if recover_via_komodo_split_stacks; then
        recovery_rc=0
      else
        recovery_rc=$?
      fi
      ;;
    komodo_procedure)
      if recover_via_komodo_procedure; then
        recovery_rc=0
      else
        recovery_rc=$?
      fi
      ;;
    *)
      announce "unknown RECOVERY_METHOD: ${RECOVERY_METHOD}"
      recovery_rc=1
      ;;
  esac

  wait_for_sab "$api_key" || true

  if (( kuma_started_by_script == 1 )); then
    run_kuma_helper stop || true
  fi

  (( recovery_rc == 0 )) || return "$recovery_rc"
}

is_active_download() {

  local status="$1"
  local mbleft="$2"

  [[ "$status" == "Downloading" ]] || return 1
  awk -v mbleft="$mbleft" 'BEGIN { exit !(mbleft > 0) }'
}

main() {
  local api_key queue_json status mbleft now elapsed delta_mb avg_mbps cooldown_until
  local below_threshold queue_grew percent_of_threshold remaining_cooldown current_speed_mbps
  local simulation_active cooldown_override_for_test active_download current_nzo_id

  acquire_lock
  reset_log_if_needed
  require_command awk
  require_command curl
  require_command jq

  simulation_active=0
  cooldown_override_for_test=0
  active_download=0

  if [[ "$FORCE_LOW_SPEED_TEST" == "1" ]]; then
    simulation_active=1
    if ! is_non_negative_decimal "$FORCE_LOW_SPEED_MBPS"; then
      announce "simulation: FORCE_LOW_SPEED_MBPS must be a non-negative decimal value"
      exit 1
    fi
    if [[ "$IGNORE_COOLDOWN_FOR_TEST" == "1" ]]; then
      cooldown_override_for_test=1
    fi
  fi

  [[ -f "$SAB_CONFIG" ]] || exit 0
  api_key="$(read_misc_value api_key)"
  [[ -n "$api_key" ]] || exit 0

  load_state

  if ! queue_json="$(fetch_queue "$api_key" 2>/dev/null)"; then
    announce "sab api request failed"
    exit 0
  fi

  status="$(jq -r '.queue.status // empty' <<< "$queue_json")"
  mbleft="$(jq -r '.queue.mbleft // empty' <<< "$queue_json")"
  current_nzo_id="$(jq -r '.queue.slots[0].nzo_id // empty' <<< "$queue_json")"
  current_speed_mbps="$(jq -r '.queue.kbpersec // 0' <<< "$queue_json" | awk '{ printf "%.2f", $1 / 1024 }')"
  now="$(date +%s)"

  if [[ -z "$status" || -z "$mbleft" ]]; then
    announce "queue data incomplete, skipping run"
    exit 0
  fi

  announce "status=${status}, current=${current_speed_mbps} MB/s, remaining=${mbleft} MB, threshold=${THRESHOLD_MBPS} MB/s, window=${AVERAGE_WINDOW_MINUTES} min"

  if is_active_download "$status" "$mbleft"; then
    active_download=1
  fi

  if (( simulation_active == 1 )); then
    announce "simulation: low-speed test enabled"
    announce "simulation: forced average=${FORCE_LOW_SPEED_MBPS} MB/s, cooldown_override=${cooldown_override_for_test}, restart_enabled=${RESTART_ENABLED}"
    announce "simulation: skipping baseline wait and sample window checks for this run"
    if (( active_download == 1 )); then
      announce "simulation: real queue is active; threshold evaluation uses the forced average"
    else
      announce "simulation: real queue is not active; bypassing the active-download requirement for this test run"
    fi
    if [[ -n "${PREV_MBLEFT}" && "$PREV_TS" -gt 0 ]]; then
      elapsed=$(( now - PREV_TS ))
      if (( elapsed < 0 )); then
        elapsed=0
      fi
    else
      elapsed=0
    fi
    avg_mbps="$FORCE_LOW_SPEED_MBPS"
  else
    if (( active_download == 0 )); then
      clear_baseline "$LAST_RESTART_TS"
      announce "no active download detected, nothing to do"
      exit 0
    fi

    if [[ -z "${PREV_MBLEFT}" || "$PREV_TS" -le 0 ]]; then
      save_baseline "$now" "$mbleft" "$current_nzo_id" "$LAST_RESTART_TS"
      announce "baseline sample stored, waiting for next run"
      exit 0
    fi

    if [[ -z "${PREV_NZO_ID}" && -n "$current_nzo_id" ]]; then
      save_baseline "$now" "$mbleft" "$current_nzo_id" "$LAST_RESTART_TS"
      announce "queue identity baseline initialized, waiting for next run"
      exit 0
    fi

    if [[ -n "$PREV_NZO_ID" && -n "$current_nzo_id" && "$PREV_NZO_ID" != "$current_nzo_id" ]]; then
      save_baseline "$now" "$mbleft" "$current_nzo_id" "$LAST_RESTART_TS"
      announce "queue identity changed from ${PREV_NZO_ID} to ${current_nzo_id}, baseline reset"
      exit 0
    fi

    delta_mb="$(awk -v prev="$PREV_MBLEFT" -v curr="$mbleft" 'BEGIN { printf "%.6f", prev - curr }')"
    queue_grew=0
    if awk -v delta="$delta_mb" 'BEGIN { exit !(delta < -1) }'; then
      queue_grew=1
    fi

    if (( queue_grew == 1 )); then
      save_baseline "$now" "$mbleft" "$current_nzo_id" "$LAST_RESTART_TS"
      announce "queue grew by more than 1 MB during warmup, baseline reset"
      exit 0
    fi

    elapsed=$(( now - PREV_TS ))
    if (( elapsed < SAMPLE_WINDOW_SECONDS )); then
      announce "sample age ${elapsed}s is below target window ${SAMPLE_WINDOW_SECONDS}s, waiting"
      exit 0
    fi

    avg_mbps="$(awk -v delta="$delta_mb" -v elapsed="$elapsed" '
      BEGIN {
        if (delta < 0) {
          delta = 0
        }
        if (elapsed <= 0) {
          printf "0.000000"
        } else {
          printf "%.6f", delta / elapsed
        }
      }
    ')"
  fi

  percent_of_threshold="$(awk -v avg="$avg_mbps" -v threshold="$THRESHOLD_MBPS" 'BEGIN {
    if (threshold <= 0) {
      printf "0.0"
    } else {
      printf "%.1f", (avg / threshold) * 100
    }
  }')"

  below_threshold=0
  if awk -v avg="$avg_mbps" -v threshold="$THRESHOLD_MBPS" 'BEGIN { exit !(avg < threshold) }'; then
    below_threshold=1
  fi

  if (( simulation_active == 1 )); then
    announce "simulation: average=${avg_mbps} MB/s over ${elapsed}s (${percent_of_threshold}% of threshold ${THRESHOLD_MBPS} MB/s)"
  else
    announce "average=${avg_mbps} MB/s over ${elapsed}s (${percent_of_threshold}% of threshold ${THRESHOLD_MBPS} MB/s)"
  fi

  if (( below_threshold == 1 )); then
    cooldown_until=$(( LAST_RESTART_TS + COOLDOWN_SECONDS ))
    if (( simulation_active == 1 && cooldown_override_for_test == 1 )); then
      announce "simulation: cooldown override is active; proceeding immediately"
      announce "speed is below threshold, starting recovery via ${RECOVERY_METHOD}"
      recover_stack "$api_key"
      LAST_RESTART_TS="$now"
    elif (( now >= cooldown_until )); then
      if (( simulation_active == 1 )); then
        announce "simulation: cooldown is not active for this run"
      fi
      announce "speed is below threshold, starting recovery via ${RECOVERY_METHOD}"
      recover_stack "$api_key"
      LAST_RESTART_TS="$now"
    else
      remaining_cooldown=$(( cooldown_until - now ))
      announce "speed is below threshold, but cooldown is still active for ${remaining_cooldown}s"
      if (( simulation_active == 1 )); then
        if [[ "$KUMA_MAINTENANCE_ENABLED" == "1" ]]; then
          announce "simulation: kuma helper would not start because cooldown is still active"
        fi
      fi
    fi
  else
    announce "speed is above threshold, no restart needed"
  fi

  if (( simulation_active == 1 && active_download == 0 )); then
    clear_baseline "$LAST_RESTART_TS"
  else
    save_state "$now" "$mbleft" "$current_nzo_id" "$LAST_RESTART_TS"
  fi
}

main "$@"
