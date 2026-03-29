#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KUMA_ENV_FILE="${KUMA_ENV_FILE:-${SCRIPT_DIR}/.env}"

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

load_env_file "$KUMA_ENV_FILE"

# User settings: override these via .env in the same directory.
APPDATA_ROOT="${APPDATA_ROOT:-/mnt/user/appdata}"            # Base appdata directory on the host.
KUMA_CONTAINER_NAME="${KUMA_CONTAINER_NAME:-uptime-kuma}"           # Uptime Kuma container name for docker exec based control.
KUMA_BASE_URL="${KUMA_BASE_URL:-http://127.0.0.1:3001}"       # Uptime Kuma URL as seen from inside the container.
KUMA_DB_FILE="${KUMA_DB_FILE:-${APPDATA_ROOT}/uptimekuma/kuma.db}" # Host path to kuma.db for maintenance lookup.
KUMA_DEFAULT_MAINTENANCE_ID="${KUMA_DEFAULT_MAINTENANCE_ID:-}"              # Optional existing dedicated manual maintenance ID to toggle.
KUMA_DEFAULT_MAINTENANCE_TITLE="${KUMA_DEFAULT_MAINTENANCE_TITLE:-SABnzbd Recovery}" # Auto-created manual maintenance title when no ID is set.
KUMA_DEFAULT_MAINTENANCE_DESCRIPTION="${KUMA_DEFAULT_MAINTENANCE_DESCRIPTION:-Triggered by monitor_sab_speed.sh during SABnzbd recovery.}" # Description for auto-created maintenance.
KUMA_DEFAULT_MONITOR_IDS="${KUMA_DEFAULT_MONITOR_IDS:-28,41}"                 # Comma-separated monitor IDs for auto-created maintenance, for example 28,41.

LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/monitor_sab_speed.log}"
STATE_FILE="${KUMA_STATE_FILE:-${SCRIPT_DIR}/monitor_sab_speed_kuma.state}"
VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-1}"
KUMA_CONTAINER="${KUMA_CONTAINER:-${KUMA_CONTAINER_NAME}}"
KUMA_URL="${KUMA_URL:-${KUMA_BASE_URL}}"
KUMA_DB_PATH="${KUMA_DB_PATH:-${KUMA_DB_FILE}}"
KUMA_MAINTENANCE_ID="${KUMA_MAINTENANCE_ID:-${KUMA_DEFAULT_MAINTENANCE_ID}}"
KUMA_MAINTENANCE_TITLE="${KUMA_MAINTENANCE_TITLE:-${KUMA_DEFAULT_MAINTENANCE_TITLE}}"
KUMA_MAINTENANCE_DESCRIPTION="${KUMA_MAINTENANCE_DESCRIPTION:-${KUMA_DEFAULT_MAINTENANCE_DESCRIPTION}}"
KUMA_MONITOR_IDS="${KUMA_MONITOR_IDS:-${KUMA_DEFAULT_MONITOR_IDS}}"
KUMA_AUTH_TOKEN="${KUMA_AUTH_TOKEN:-}"
KUMA_USERNAME="${KUMA_USERNAME:-}"
KUMA_PASSWORD="${KUMA_PASSWORD:-}"
KUMA_SOCKET_TIMEOUT_MS="${KUMA_SOCKET_TIMEOUT_MS:-20000}"
KUMA_SOCKET_RETRIES="${KUMA_SOCKET_RETRIES:-3}"
KUMA_SOCKET_RETRY_SLEEP_SECONDS="${KUMA_SOCKET_RETRY_SLEEP_SECONDS:-2}"

STATE_MAINTENANCE_ID=""
STATE_STARTED_BY_SCRIPT=0

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

announce_stderr() {
  local message="$1"
  log "$message"
  if [[ "$VERBOSE_OUTPUT" == "1" ]]; then
    printf '%s %s\n' "$(date '+%F %T')" "$message" >&2
  fi
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    announce "kuma: missing required command: $cmd"
    exit 1
  }
}

is_positive_integer() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

sql_escape() {
  local value="$1"
  value=${value//\'/\'\'}
  printf '%s' "$value"
}

read_kuma_scalar() {
  local sql="$1"
  sqlite3 -noheader -batch "$KUMA_DB_PATH" "$sql" 2>/dev/null | head -n 1
}

save_state() {
  local maintenance_id="$1"
  local started_by_script="$2"

  cat > "$STATE_FILE" <<STATEEOF
STATE_MAINTENANCE_ID="${maintenance_id}"
STATE_STARTED_BY_SCRIPT=${started_by_script}
STATEEOF
}

clear_state() {
  rm -f "$STATE_FILE"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  # shellcheck disable=SC1090
  . "$STATE_FILE"
}

validate_kuma_monitor_ids() {
  local cleaned id

  cleaned="${KUMA_MONITOR_IDS//[[:space:]]/}"
  [[ -n "$cleaned" ]] || return 1

  IFS=',' read -r -a kuma_monitor_id_list <<< "$cleaned"
  for id in "${kuma_monitor_id_list[@]}"; do
    [[ -n "$id" ]] || continue
    if ! is_positive_integer "$id"; then
      announce_stderr "kuma: invalid monitor id '${id}' in KUMA_MONITOR_IDS"
      return 1
    fi
  done

  printf '%s' "$cleaned"
}

run_kuma_socket_action() {
  local action="$1"
  local maintenance_id="${2:-}"
  local monitor_ids="${3:-}"
  local heartbeat_monitor_ids="${4:-}"

  docker exec -i \
    -e KUMA_ACTION="$action" \
    -e KUMA_URL="$KUMA_URL" \
    -e KUMA_AUTH_TOKEN="$KUMA_AUTH_TOKEN" \
    -e KUMA_USERNAME="$KUMA_USERNAME" \
    -e KUMA_PASSWORD="$KUMA_PASSWORD" \
    -e KUMA_SOCKET_TIMEOUT_MS="$KUMA_SOCKET_TIMEOUT_MS" \
    -e KUMA_MAINTENANCE_ID="$maintenance_id" \
    -e KUMA_MAINTENANCE_TITLE="$KUMA_MAINTENANCE_TITLE" \
    -e KUMA_MAINTENANCE_DESCRIPTION="$KUMA_MAINTENANCE_DESCRIPTION" \
    -e KUMA_MONITOR_IDS="$monitor_ids" \
    -e KUMA_HEARTBEAT_MONITOR_IDS="$heartbeat_monitor_ids" \
    "$KUMA_CONTAINER" \
    node - <<'NODE'
const { io } = require("socket.io-client");

const action = process.env.KUMA_ACTION || "";
const url = process.env.KUMA_URL || "http://127.0.0.1:3001";
const authToken = process.env.KUMA_AUTH_TOKEN || "";
const username = process.env.KUMA_USERNAME || "";
const password = process.env.KUMA_PASSWORD || "";
const socketTimeout = Number.parseInt(process.env.KUMA_SOCKET_TIMEOUT_MS || "20000", 10);
const maintenanceID = process.env.KUMA_MAINTENANCE_ID || "";
const title = process.env.KUMA_MAINTENANCE_TITLE || "SABnzbd Recovery";
const description = process.env.KUMA_MAINTENANCE_DESCRIPTION || "Triggered by monitor_sab_speed.sh during SABnzbd recovery.";
const heartbeatMonitorIds = (process.env.KUMA_HEARTBEAT_MONITOR_IDS || "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean)
  .map((value) => {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`Invalid heartbeat monitor id: ${value}`);
    }
    return parsed;
  });
const monitorIds = (process.env.KUMA_MONITOR_IDS || "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean)
  .map((value) => {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`Invalid monitor id: ${value}`);
    }
    return parsed;
  });

function emitAck(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (!finished) {
        finished = true;
        reject(new Error(`${event} timed out`));
      }
    }, socketTimeout);

    socket.emit(event, ...args, (response) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);

      if (!response || response.ok !== true) {
        reject(new Error(response && response.msg ? response.msg : `${event} failed`));
        return;
      }

      resolve(response);
    });
  });
}

async function connectSocket() {
  const socket = io(url, {
    transports: ["websocket"],
    reconnection: false,
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`connect timed out for ${url}`));
    }, socketTimeout);

    socket.once("connect", () => {
      clearTimeout(timer);
      resolve();
    });

    socket.once("connect_error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });

  return socket;
}

async function login(socket) {
  if (authToken) {
    await emitAck(socket, "loginByToken", authToken);
    return;
  }

  if (!username || !password) {
    throw new Error("KUMA_AUTH_TOKEN or KUMA_USERNAME/KUMA_PASSWORD is required");
  }

  await emitAck(socket, "login", { username, password });
}

(async () => {
  const socket = await connectSocket();

  try {
    await login(socket);

    if (action === "create") {
      const maintenance = {
        title,
        description,
        strategy: "manual",
        intervalDay: null,
        active: false,
        dateRange: [null],
        timeRange: [null, null],
        weekdays: [],
        daysOfMonth: [],
        cron: null,
        durationMinutes: 0,
        timezoneOption: "SAME_AS_SERVER",
      };

      const response = await emitAck(socket, "addMaintenance", maintenance);
      const createdID = response.maintenanceID;

      if (monitorIds.length > 0) {
        await emitAck(socket, "addMonitorMaintenance", createdID, monitorIds.map((id) => ({ id })));
      }

      process.stdout.write(`MAINTENANCE_ID=${createdID}\n`);
    } else if (action === "set_monitors") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for set_monitors");
      }

      await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), monitorIds.map((id) => ({ id })));
      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
    } else if (action === "resume") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for resume");
      }

      await emitAck(socket, "resumeMaintenance", Number(maintenanceID));
      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
    } else if (action === "resume_monitors") {
      if (monitorIds.length === 0) {
        throw new Error("At least one monitor id is required for resume_monitors");
      }

      for (const monitorId of monitorIds) {
        await emitAck(socket, "resumeMonitor", monitorId);
      }

      process.stdout.write(`MONITOR_IDS=${monitorIds.join(",")}\n`);
    } else if (action === "start_bundle") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for start_bundle");
      }

      if (monitorIds.length > 0) {
        await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), monitorIds.map((id) => ({ id })));
      }

      await emitAck(socket, "resumeMaintenance", Number(maintenanceID));

      for (const monitorId of heartbeatMonitorIds) {
        await emitAck(socket, "resumeMonitor", monitorId);
      }

      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
      process.stdout.write(`MONITOR_IDS=${monitorIds.join(",")}\n`);
    } else if (action === "pause") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for pause");
      }

      await emitAck(socket, "pauseMaintenance", Number(maintenanceID));
      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
    } else if (action === "stop_bundle") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for stop_bundle");
      }

      await emitAck(socket, "pauseMaintenance", Number(maintenanceID));
      await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), []);

      for (const monitorId of heartbeatMonitorIds) {
        await emitAck(socket, "resumeMonitor", monitorId);
      }

      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
      process.stdout.write(`MONITOR_IDS=${monitorIds.join(",")}\n`);
    } else {
      throw new Error(`Unsupported action: ${action}`);
    }
  } finally {
    socket.close();
  }
})().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
NODE
}

run_kuma_socket_action_with_retry() {
  local action="$1"
  local maintenance_id="${2:-}"
  local monitor_ids="${3:-}"
  local heartbeat_monitor_ids="${4:-}"
  local attempt=1
  local max_attempts sleep_seconds output

  max_attempts="$KUMA_SOCKET_RETRIES"
  sleep_seconds="$KUMA_SOCKET_RETRY_SLEEP_SECONDS"

  if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
    max_attempts=3
  fi

  while true; do
    if output="$(run_kuma_socket_action "$action" "$maintenance_id" "$monitor_ids" "$heartbeat_monitor_ids" 2>>"$LOG_FILE")"; then
      printf '%s' "$output"
      return 0
    fi

    if (( attempt >= max_attempts )); then
      return 1
    fi

    announce_stderr "kuma: socket action '${action}' failed on attempt ${attempt}/${max_attempts}, retrying in ${sleep_seconds}s"
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

create_kuma_maintenance() {
  local monitor_ids="$1"
  local output maintenance_id

  announce_stderr "kuma: creating manual maintenance '${KUMA_MAINTENANCE_TITLE}'"
  if ! output="$(run_kuma_socket_action_with_retry create "" "$monitor_ids")"; then
    announce_stderr "kuma: failed to create manual maintenance '${KUMA_MAINTENANCE_TITLE}'"
    return 1
  fi

  maintenance_id="$(awk -F '=' '/^MAINTENANCE_ID=/ { print $2; exit }' <<< "$output")"
  if ! is_positive_integer "$maintenance_id"; then
    announce_stderr "kuma: create action did not return a valid maintenance id"
    return 1
  fi

  announce_stderr "kuma: created manual maintenance id=${maintenance_id}"
  printf '%s' "$maintenance_id"
}

get_active_kuma_monitor_ids() {
  local monitor_ids="$1"
  local active_ids

  [[ -n "$monitor_ids" ]] || return 0

  active_ids="$(read_kuma_scalar "select group_concat(id, ',') from monitor where active = 1 and id in (${monitor_ids});")"
  printf '%s' "$active_ids"
}

resolve_kuma_maintenance_id() {
  local strategy escaped_title existing_id monitor_ids

  if [[ -n "$KUMA_MAINTENANCE_ID" ]]; then
    if ! is_positive_integer "$KUMA_MAINTENANCE_ID"; then
      announce_stderr "kuma: KUMA_MAINTENANCE_ID must be a positive integer"
      return 1
    fi

    strategy="$(read_kuma_scalar "select strategy from maintenance where id = ${KUMA_MAINTENANCE_ID};")"
    if [[ -z "$strategy" ]]; then
      announce_stderr "kuma: maintenance id=${KUMA_MAINTENANCE_ID} was not found"
      return 1
    fi
    if [[ "$strategy" != "manual" ]]; then
      announce_stderr "kuma: maintenance id=${KUMA_MAINTENANCE_ID} is strategy=${strategy}; use a dedicated manual maintenance"
      return 1
    fi

    printf '%s' "$KUMA_MAINTENANCE_ID"
    return 0
  fi

  escaped_title="$(sql_escape "$KUMA_MAINTENANCE_TITLE")"
  existing_id="$(read_kuma_scalar "select id from maintenance where title = '${escaped_title}' and strategy = 'manual' order by id limit 1;")"
  if is_positive_integer "$existing_id"; then
    announce_stderr "kuma: reusing manual maintenance id=${existing_id} title='${KUMA_MAINTENANCE_TITLE}'"
    printf '%s' "$existing_id"
    return 0
  fi

  monitor_ids="$(validate_kuma_monitor_ids)" || {
    announce_stderr "kuma: KUMA_MONITOR_IDS is required when auto-creating a maintenance"
    return 1
  }

  create_kuma_maintenance "$monitor_ids"
}

ensure_kuma_maintenance() {
  local maintenance_id

  require_command docker
  require_command sqlite3

  if [[ ! -f "$KUMA_DB_PATH" ]]; then
    announce_stderr "kuma: database not found at ${KUMA_DB_PATH}"
    return 1
  fi

  maintenance_id="$(resolve_kuma_maintenance_id)" || return 1

  printf '%s' "$maintenance_id"
}

kuma_maintenance_is_active() {
  local maintenance_id="$1"
  local active_value

  active_value="$(read_kuma_scalar "select active from maintenance where id = ${maintenance_id};")"
  [[ "$active_value" == "1" ]]
}

start_action() {
  local maintenance_id monitor_ids active_monitor_ids

  maintenance_id="$(ensure_kuma_maintenance)" || return 1
  monitor_ids="$(validate_kuma_monitor_ids || true)"
  active_monitor_ids="$(get_active_kuma_monitor_ids "$monitor_ids")"

  if kuma_maintenance_is_active "$maintenance_id"; then
    announce "kuma: maintenance id=${maintenance_id} is already active, leaving it active"
    save_state "$maintenance_id" 0
    return 0
  fi

  announce "kuma: starting maintenance id=${maintenance_id}"
  if ! run_kuma_socket_action_with_retry start_bundle "$maintenance_id" "$monitor_ids" "$active_monitor_ids" >/dev/null; then
    announce "kuma: failed to start maintenance id=${maintenance_id}"
    clear_state
    return 1
  fi

  if [[ -n "$active_monitor_ids" ]]; then
    announce "kuma: synced monitor mapping and refreshed heartbeats for monitor ids=${active_monitor_ids}"
  else
    announce "kuma: start completed without active monitor heartbeat refresh"
  fi
  announce "kuma: maintenance id=${maintenance_id} is active"
  save_state "$maintenance_id" 1
}

stop_action() {
  local monitor_ids active_monitor_ids

  load_state
  monitor_ids="$(validate_kuma_monitor_ids || true)"
  active_monitor_ids="$(get_active_kuma_monitor_ids "$monitor_ids")"

  if [[ -z "$STATE_MAINTENANCE_ID" ]]; then
    announce "kuma: no helper-owned maintenance state to stop"
    return 0
  fi

  if [[ "$STATE_STARTED_BY_SCRIPT" != "1" ]]; then
    announce "kuma: leaving maintenance id=${STATE_MAINTENANCE_ID} active because it was already active before recovery"
    clear_state
    return 0
  fi

  if ! is_positive_integer "$STATE_MAINTENANCE_ID"; then
    announce "kuma: helper state contains an invalid maintenance id"
    clear_state
    return 1
  fi

  if ! kuma_maintenance_is_active "$STATE_MAINTENANCE_ID"; then
    announce "kuma: maintenance id=${STATE_MAINTENANCE_ID} is already inactive"
    if ! run_kuma_socket_action_with_retry stop_bundle "$STATE_MAINTENANCE_ID" "$monitor_ids" "$active_monitor_ids" >/dev/null; then
      announce "kuma: failed to clear inactive maintenance id=${STATE_MAINTENANCE_ID}"
      return 1
    fi
    if [[ -n "$active_monitor_ids" ]]; then
      announce "kuma: cleared monitor mapping and refreshed heartbeats for monitor ids=${active_monitor_ids}"
    else
      announce "kuma: cleared monitor mapping without active monitor heartbeat refresh"
    fi
    clear_state
    return 0
  fi

  announce "kuma: stopping maintenance id=${STATE_MAINTENANCE_ID}"
  if ! run_kuma_socket_action_with_retry stop_bundle "$STATE_MAINTENANCE_ID" "$monitor_ids" "$active_monitor_ids" >/dev/null; then
    announce "kuma: failed to stop maintenance id=${STATE_MAINTENANCE_ID}"
    return 1
  fi

  if [[ -n "$active_monitor_ids" ]]; then
    announce "kuma: cleared monitor mapping and refreshed heartbeats for monitor ids=${active_monitor_ids}"
  else
    announce "kuma: stop completed without active monitor heartbeat refresh"
  fi
  announce "kuma: maintenance id=${STATE_MAINTENANCE_ID} is inactive"
  clear_state
}

main() {
  local action="${1:-}"

  case "$action" in
    start)
      start_action
      ;;
    stop)
      stop_action
      ;;
    *)
      printf 'usage: %s {start|stop}\n' "$0" >&2
      exit 1
      ;;
  esac
}

main "$@"
