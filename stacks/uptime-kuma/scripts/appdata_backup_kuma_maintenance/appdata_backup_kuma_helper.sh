#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

if [[ -n "${KUMA_ENV_FILE:-}" ]]; then
  load_env_file "$KUMA_ENV_FILE"
else
  load_env_file "${SCRIPT_DIR}/.env"
fi

APPDATA_ROOT="${APPDATA_ROOT:-/mnt/user/appdata}"
KUMA_CONTAINER_NAME="${KUMA_CONTAINER_NAME:-uptime-kuma}"
KUMA_BASE_URL="${KUMA_BASE_URL:-http://127.0.0.1:3001}"
KUMA_DB_FILE="${KUMA_DB_FILE:-${APPDATA_ROOT}/uptimekuma/kuma.db}"
KUMA_DEFAULT_MAINTENANCE_ID="${KUMA_DEFAULT_MAINTENANCE_ID:-}"
KUMA_DEFAULT_MAINTENANCE_TITLE="${KUMA_DEFAULT_MAINTENANCE_TITLE:-Appdata Backup}"
KUMA_DEFAULT_MAINTENANCE_DESCRIPTION="${KUMA_DEFAULT_MAINTENANCE_DESCRIPTION:-Triggered by the appdata.backup pre-run/post-run hooks while Docker containers are stopped.}"
KUMA_INCLUDE_INACTIVE_MONITORS="${KUMA_INCLUDE_INACTIVE_MONITORS:-1}"
KUMA_POST_RUN_TIMEOUT_SECONDS="${KUMA_POST_RUN_TIMEOUT_SECONDS:-600}"
KUMA_POST_RUN_POLL_INTERVAL_SECONDS="${KUMA_POST_RUN_POLL_INTERVAL_SECONDS:-5}"
KUMA_POST_RUN_HTTP_TIMEOUT_SECONDS="${KUMA_POST_RUN_HTTP_TIMEOUT_SECONDS:-10}"
KUMA_POST_RUN_DNS_TIMEOUT_SECONDS="${KUMA_POST_RUN_DNS_TIMEOUT_SECONDS:-10}"
KUMA_POST_RUN_CURL_INSECURE="${KUMA_POST_RUN_CURL_INSECURE:-0}"
LOG_RESET_DAYS="${LOG_RESET_DAYS:-7}"
KUMA_HTTP_MONITOR_ALIAS_MAP="${KUMA_HTTP_MONITOR_ALIAS_MAP:-}"
if [[ -z "$KUMA_HTTP_MONITOR_ALIAS_MAP" ]]; then
  KUMA_HTTP_MONITOR_ALIAS_MAP='{}'
fi

LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/appdata_backup_kuma.log}"
STATE_FILE="${KUMA_STATE_FILE:-${SCRIPT_DIR}/appdata_backup_kuma.state}"
VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-1}"
KUMA_CONTAINER="${KUMA_CONTAINER:-${KUMA_CONTAINER_NAME}}"
KUMA_URL="${KUMA_URL:-${KUMA_BASE_URL}}"
KUMA_DB_PATH="${KUMA_DB_PATH:-${KUMA_DB_FILE}}"
KUMA_MAINTENANCE_ID="${KUMA_MAINTENANCE_ID:-${KUMA_DEFAULT_MAINTENANCE_ID}}"
KUMA_MAINTENANCE_TITLE="${KUMA_MAINTENANCE_TITLE:-${KUMA_DEFAULT_MAINTENANCE_TITLE}}"
KUMA_MAINTENANCE_DESCRIPTION="${KUMA_MAINTENANCE_DESCRIPTION:-${KUMA_DEFAULT_MAINTENANCE_DESCRIPTION}}"
KUMA_AUTH_TOKEN="${KUMA_AUTH_TOKEN:-}"
KUMA_USERNAME="${KUMA_USERNAME:-}"
KUMA_PASSWORD="${KUMA_PASSWORD:-}"
KUMA_SOCKET_TIMEOUT_MS="${KUMA_SOCKET_TIMEOUT_MS:-20000}"
KUMA_SOCKET_RETRIES="${KUMA_SOCKET_RETRIES:-3}"
KUMA_SOCKET_RETRY_SLEEP_SECONDS="${KUMA_SOCKET_RETRY_SLEEP_SECONDS:-2}"
LOG_RESET_SECONDS="${LOG_RESET_SECONDS:-$((LOG_RESET_DAYS * 86400))}"

STATE_MAINTENANCE_ID=""
STATE_STARTED_BY_SCRIPT=0
HTTP_LAST_PROBE_URL=""
HTTP_LAST_PROBE_CODE=""
HTTP_LAST_PROBE_REASON=""
HTTP_LAST_PROBE_READY=1
DNS_LAST_PROBE_REASON=""
DNS_LAST_PROBE_READY=1

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
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
  message="kuma: logfile cleared after ${LOG_RESET_DAYS} day(s)"
  printf '%s %s\n' "$(date '+%F %T')" "$message" >> "$LOG_FILE"
  if verbosity_at_least 1; then
    printf '%s %s\n' "$(date '+%F %T')" "$message"
  fi
}

verbosity_at_least() {
  local level="${1:-1}"
  local current="${VERBOSE_OUTPUT:-0}"

  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  (( current >= level ))
}

announce() {
  local message="$1"
  log "$message"
  if verbosity_at_least 1; then
    printf '%s %s\n' "$(date '+%F %T')" "$message"
  fi
}

announce_stderr() {
  local message="$1"
  log "$message"
  if verbosity_at_least 1; then
    printf '%s %s\n' "$(date '+%F %T')" "$message" >&2
  fi
}

announce_verbose() {
  local message="$1"
  log "$message"
  if verbosity_at_least 2; then
    printf '%s %s\n' "$(date '+%F %T')" "$message"
  fi
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    announce_stderr "kuma: missing required command: $cmd"
    return 1
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

json_array_length() {
  local json_input="$1"
  jq -r 'length' <<< "$json_input"
}

json_array_is_empty() {
  local json_input="$1"
  [[ "$(json_array_length "$json_input")" == "0" ]]
}

json_array_join_csv() {
  local json_input="$1"
  jq -r 'map(tostring) | join(",")' <<< "$json_input"
}

json_array_diff() {
  local left_json="$1"
  local right_json="$2"
  jq -cn --argjson left "$left_json" --argjson right "$right_json" '($left - $right) | unique | sort'
}

json_array_intersection() {
  local left_json="$1"
  local right_json="$2"
  jq -cn --argjson left "$left_json" --argjson right "$right_json" '[$left[] | select($right | index(.))] | unique | sort'
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
    -e KUMA_INCLUDE_INACTIVE_MONITORS="$KUMA_INCLUDE_INACTIVE_MONITORS" \
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
const title = process.env.KUMA_MAINTENANCE_TITLE || "Appdata Backup";
const description = process.env.KUMA_MAINTENANCE_DESCRIPTION || "";
const includeInactive = (process.env.KUMA_INCLUDE_INACTIVE_MONITORS || "1") === "1";
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

async function getMonitorList(socket) {
  return new Promise((resolve, reject) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (!finished) {
        finished = true;
        reject(new Error("monitorList timed out"));
      }
    }, socketTimeout);

    const cleanup = () => {
      clearTimeout(timer);
      socket.off("monitorList", handleMonitorList);
    };

    const handleMonitorList = (monitorMap) => {
      if (finished) {
        return;
      }

      finished = true;
      cleanup();
      resolve(monitorMap || {});
    };

    socket.once("monitorList", handleMonitorList);
    socket.emit("getMonitorList", (response) => {
      if (finished) {
        return;
      }

      if (!response || response.ok !== true) {
        finished = true;
        cleanup();
        reject(new Error(response && response.msg ? response.msg : "getMonitorList failed"));
      }
    });
  });
}

function normalizeMonitors(monitorMap) {
  return Object.values(monitorMap)
    .filter((monitor) => Number.isInteger(Number.parseInt(String(monitor.id), 10)))
    .map((monitor) => ({
      id: Number.parseInt(String(monitor.id), 10),
      active: Boolean(monitor.active),
      name: monitor.name || "",
      type: monitor.type || "",
      url: monitor.url || "",
      hostname: monitor.hostname || "",
      port: monitor.port || "",
      dns_resolve_server: monitor.dns_resolve_server || monitor.dnsResolveServer || "",
      dns_resolve_type: monitor.dns_resolve_type || monitor.dnsResolveType || "",
      conditions: Array.isArray(monitor.conditions)
        ? monitor.conditions
        : (typeof monitor.conditions === "string" && monitor.conditions
          ? JSON.parse(monitor.conditions)
          : []),
      docker_container: monitor.docker_container || monitor.dockerContainer || "",
      parent: Number.isInteger(Number.parseInt(String(monitor.parent), 10))
        ? Number.parseInt(String(monitor.parent), 10)
        : null,
    }))
    .sort((left, right) => left.id - right.id);
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
      process.stdout.write(`MAINTENANCE_ID=${response.maintenanceID}\n`);
    } else if (action === "get_monitors_json") {
      const monitorMap = await getMonitorList(socket);
      const monitors = normalizeMonitors(monitorMap);
      const selectedMonitors = includeInactive ? monitors : monitors.filter((monitor) => monitor.active);
      process.stdout.write(JSON.stringify(selectedMonitors));
    } else if (action === "start_bundle") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for start_bundle");
      }

      await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), monitorIds.map((id) => ({ id })));
      await emitAck(socket, "resumeMaintenance", Number(maintenanceID));

      for (const monitorId of heartbeatMonitorIds) {
        await emitAck(socket, "resumeMonitor", monitorId);
      }

      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
      process.stdout.write(`MONITOR_IDS=${monitorIds.join(",")}\n`);
    } else if (action === "sync_bundle") {
      if (!maintenanceID) {
        throw new Error("Maintenance ID is required for sync_bundle");
      }

      if (monitorIds.length > 0) {
        await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), monitorIds.map((id) => ({ id })));
        await emitAck(socket, "resumeMaintenance", Number(maintenanceID));
      } else {
        await emitAck(socket, "pauseMaintenance", Number(maintenanceID));
        await emitAck(socket, "addMonitorMaintenance", Number(maintenanceID), []);
      }

      for (const monitorId of heartbeatMonitorIds) {
        await emitAck(socket, "resumeMonitor", monitorId);
      }

      process.stdout.write(`MAINTENANCE_ID=${maintenanceID}\n`);
      process.stdout.write(`MONITOR_IDS=${monitorIds.join(",")}\n`);
      process.stdout.write(`HEARTBEAT_MONITOR_IDS=${heartbeatMonitorIds.join(",")}\n`);
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
  local output maintenance_id

  announce_stderr "kuma: creating manual maintenance '${KUMA_MAINTENANCE_TITLE}'"
  if ! output="$(run_kuma_socket_action_with_retry create)"; then
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

fetch_kuma_monitors_json() {
  local output

  if ! output="$(run_kuma_socket_action_with_retry get_monitors_json)"; then
    announce_stderr "kuma: failed to fetch monitor list from socket"
    return 1
  fi

  jq -c '.' <<< "$output"
}

selected_monitor_ids_from_json() {
  local monitors_json="$1"
  jq -c 'map(.id) | unique | sort' <<< "$monitors_json"
}

active_monitor_ids_from_json() {
  local monitors_json="$1"
  jq -c 'map(select(.active == true) | .id) | unique | sort' <<< "$monitors_json"
}

fetch_docker_containers_json() {
  local container_names=()

  mapfile -t container_names < <(docker ps -a --format '{{.Names}}' | sort)
  if (( ${#container_names[@]} == 0 )); then
    printf '[]'
    return 0
  fi

  docker inspect "${container_names[@]}" | jq -c --argjson host_alias_map "$KUMA_HTTP_MONITOR_ALIAS_MAP" '
    [
      .[] | (.Name | ltrimstr("/")) as $container_name
      | {
        name: $container_name,
        state: (.State.Status // ""),
        has_healthcheck: ((.State.Health != null) or (.Config.Healthcheck != null)),
        health_status: (.State.Health.Status // ""),
        hosts: (
          [
            ((.Config.Labels // {}) | to_entries[]? | select(.key | test("^traefik\\.http\\.routers\\..*\\.rule$")) | .value) as $rule
            | (
                (try ($rule | match("Host\\([^)]*\\)").string) catch "")
                | [scan("`[^`]+`")]
                | map(.[1:-1])
              )[]
          ]
          + (($host_alias_map[$container_name] // []) | map(select(type == "string" and length > 0)))
          | unique | sort
        )
      }
    ]
  '
}

fetch_docker_container_status_json() {
  local container_names=()

  mapfile -t container_names < <(docker ps -a --format '{{.Names}}' | sort)
  if (( ${#container_names[@]} == 0 )); then
    printf '[]'
    return 0
  fi

  docker inspect "${container_names[@]}" | jq -c '
    [
      .[] | {
        name: (.Name | ltrimstr("/")),
        state: (.State.Status // ""),
        has_healthcheck: ((.State.Health != null) or (.Config.Healthcheck != null)),
        health_status: (.State.Health.Status // "")
      }
    ]
  '
}

build_release_plan_json() {
  local monitors_json="$1"
  local containers_json="$2"

  jq -cn \
    --argjson monitors "$monitors_json" \
    --argjson containers "$containers_json" \
    '
    def host_from_url:
      try (capture("^[A-Za-z]+://(?<host>[^/:?#]+)").host) catch null;
    def http_monitors_for($selected; $hosts):
      [
        $selected[] | select(.type == "http") as $monitor
        | (($monitor.url // "") | host_from_url) as $host
        | select($host != null and ($hosts | index($host)))
        | {
            id: $monitor.id,
            url: ($monitor.url // ""),
            active: ($monitor.active == true),
            name: ($monitor.name // "")
          }
      ] | unique_by(.id) | sort_by(.id);
    def docker_monitor_ids_for($selected; $name):
      [$selected[] | select(.type == "docker" and ((.docker_container // "") == $name)) | .id] | unique | sort;
    ($monitors | sort_by(.id)) as $selected
    | [
        $containers[] | {
          name: .name,
          hosts: (.hosts // []),
          docker_monitor_ids: docker_monitor_ids_for($selected; .name),
          http_monitors: http_monitors_for($selected; (.hosts // []))
        }
        | .http_monitor_ids = (.http_monitors | map(.id))
        | .monitor_ids = ((.docker_monitor_ids + .http_monitor_ids) | unique | sort)
        | select((.monitor_ids | length) > 0)
      ] as $container_plan
    | ($container_plan | map(.monitor_ids[]) | unique | sort) as $mapped_ids
    | [
        $selected[] as $monitor
        | select(($mapped_ids | index($monitor.id)) | not)
        | {
            id: $monitor.id,
            active: ($monitor.active == true),
            name: ($monitor.name // ""),
            type: ($monitor.type // ""),
            url: ($monitor.url // ""),
            hostname: ($monitor.hostname // ""),
            port: ($monitor.port // ""),
            dns_resolve_server: ($monitor.dns_resolve_server // ""),
            dns_resolve_type: ($monitor.dns_resolve_type // ""),
            conditions: ($monitor.conditions // []),
            docker_container: ($monitor.docker_container // "")
          }
      ] as $unmapped_monitors
    | {
        selected_monitor_ids: ($selected | map(.id) | unique | sort),
        active_monitor_ids: ($selected | map(select(.active == true) | .id) | unique | sort),
        containers: $container_plan,
        unmapped_monitor_ids: ($unmapped_monitors | map(.id) | unique | sort),
        unmapped_monitors: ($unmapped_monitors | sort_by(.id))
      }
  '
}

container_status_blocking_reason() {
  local container_name="$1"
  local status_json="$2"

  jq -r --arg name "$container_name" '
    first(.[] | select(.name == $name)) as $container
    | if $container == null then
        "container missing"
      elif $container.state != "running" then
        "state=" + ($container.state // "unknown")
      elif $container.has_healthcheck == true and ($container.health_status == "starting" or $container.health_status == "unhealthy") then
        "health=" + ($container.health_status // "unknown")
      else
        ""
      end
  ' <<< "$status_json"
}

probe_http_url() {
  local url="$1"
  local response status_code curl_exit
  local curl_args=(
    --silent
    --output /dev/null
    --write-out 'HTTPSTATUS:%{http_code}'
    --connect-timeout "$KUMA_POST_RUN_HTTP_TIMEOUT_SECONDS"
    --max-time "$KUMA_POST_RUN_HTTP_TIMEOUT_SECONDS"
  )

  HTTP_LAST_PROBE_URL="$url"
  HTTP_LAST_PROBE_CODE=""
  HTTP_LAST_PROBE_REASON=""
  HTTP_LAST_PROBE_READY=1

  if [[ "$KUMA_POST_RUN_CURL_INSECURE" == "1" ]]; then
    curl_args+=(-k)
  fi

  set +e
  response="$(curl "${curl_args[@]}" "$url" 2>/dev/null)"
  curl_exit=$?
  set -e

  status_code="${response##*HTTPSTATUS:}"
  if [[ "$status_code" == "$response" ]]; then
    status_code="000"
  fi

  HTTP_LAST_PROBE_CODE="$status_code"

  case "$status_code" in
    2??|3??|401|403)
      HTTP_LAST_PROBE_REASON="ready"
      HTTP_LAST_PROBE_READY=1
      return 0
      ;;
    404)
      HTTP_LAST_PROBE_REASON="http=404"
      ;;
    000)
      if [[ "$curl_exit" == "60" ]]; then
        HTTP_LAST_PROBE_REASON="tls=waiting"
      else
        HTTP_LAST_PROBE_REASON="connect=waiting"
      fi
      ;;
    *)
      HTTP_LAST_PROBE_REASON="http=${status_code}"
      ;;
  esac

  HTTP_LAST_PROBE_READY=0
  return 1
}

http_url_is_ready() {
  local url="$1"
  probe_http_url "$url"
}

probe_dns_monitor() {
  local monitor_json="$1"
  local output exit_code

  DNS_LAST_PROBE_REASON=""
  DNS_LAST_PROBE_READY=1

  set +e
  output="$(
    docker exec -i \
      -e KUMA_DNS_MONITOR_JSON="$monitor_json" \
      -e KUMA_DNS_TIMEOUT_SECONDS="$KUMA_POST_RUN_DNS_TIMEOUT_SECONDS" \
      "$KUMA_CONTAINER" \
      node - <<'NODE'
const { Resolver } = require("node:dns/promises");
const net = require("node:net");

function parseMonitor() {
  const raw = process.env.KUMA_DNS_MONITOR_JSON || "{}";
  return JSON.parse(raw);
}

function parseConditions(value) {
  if (Array.isArray(value)) {
    return value;
  }
  if (typeof value === "string" && value) {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function normalizeServerList(value) {
  return String(value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

async function resolveResolverServers(value) {
  const entries = normalizeServerList(value);
  if (entries.length === 0) {
    throw new Error("resolver server missing");
  }

  const resolver = new Resolver();
  const resolved = await Promise.all(entries.map(async (entry) => {
    if (net.isIP(entry)) {
      return [entry];
    }

    const [v4, v6] = await Promise.allSettled([resolver.resolve4(entry), resolver.resolve6(entry)]);
    return [
      ...(v4.status === "fulfilled" ? v4.value : []),
      ...(v6.status === "fulfilled" ? v6.value : []),
    ];
  }));

  return resolved.flat().filter(Boolean);
}

async function dnsResolve(hostname, resolverServers, resolverPort, rrtype) {
  const resolver = new Resolver({
    timeout: Math.max(1, Number.parseInt(process.env.KUMA_DNS_TIMEOUT_SECONDS || "10", 10)) * 1000,
    tries: 1,
  });
  resolver.setServers(resolverServers.map((server) => `[${server}]:${resolverPort}`));

  if (rrtype === "PTR") {
    return await resolver.reverse(hostname);
  }

  return await resolver.resolve(hostname, rrtype);
}

function testOperator(operator, variable, value) {
  switch (operator) {
    case "equals":
      return variable === value;
    case "not_equals":
      return variable !== value;
    case "contains":
      return Array.isArray(variable) ? variable.includes(value) : String(variable).includes(value);
    case "not_contains":
      return Array.isArray(variable) ? !variable.includes(value) : !String(variable).includes(value);
    case "starts_with":
      return String(variable).startsWith(value);
    case "not_starts_with":
      return !String(variable).startsWith(value);
    case "ends_with":
      return String(variable).endsWith(value);
    case "not_ends_with":
      return !String(variable).endsWith(value);
    default:
      return false;
  }
}

function evaluateConditions(conditions, data) {
  if (!Array.isArray(conditions) || conditions.length === 0) {
    return true;
  }

  const evaluateNode = (node) => {
    if (!node || typeof node !== "object") {
      return false;
    }

    if (node.type === "group") {
      return evaluateSequence(Array.isArray(node.children) ? node.children : []);
    }

    if (node.type === "expression") {
      const variable = data[node.variable];
      return testOperator(node.operator, variable, node.value);
    }

    return false;
  };

  const evaluateSequence = (nodes) => {
    let result = null;

    for (const node of nodes) {
      const current = evaluateNode(node);
      const andOr = node && node.andOr === "or" ? "or" : "and";

      if (result === null) {
        result = current;
      } else if (andOr === "or") {
        result = result || current;
      } else {
        result = result && current;
      }
    }

    return result === null ? true : result;
  };

  return evaluateSequence(conditions);
}

function buildDnsOutcome(rrtype, dnsRes, conditions) {
  const matchesRecord = (record) => evaluateConditions(conditions, { record });

  switch (rrtype) {
    case "A":
    case "AAAA":
    case "PTR": {
      const message = `Records: ${dnsRes.join(" | ")}`;
      return { ok: dnsRes.some((record) => matchesRecord(record)), message };
    }

    case "TXT": {
      const flat = dnsRes.flat();
      const message = `Records: ${flat.join(" | ")}`;
      return { ok: flat.some((record) => matchesRecord(record)), message };
    }

    case "CNAME": {
      const record = dnsRes[0];
      return { ok: matchesRecord(record), message: record };
    }

    case "CAA": {
      const values = dnsRes.map((record) => record.issue).filter(Boolean);
      return {
        ok: values.some((record) => matchesRecord(record)),
        message: `Records: ${values.join(" | ")}`,
      };
    }

    case "MX": {
      return {
        ok: dnsRes.some((record) => matchesRecord(record.exchange)),
        message: dnsRes
          .map((record) => `Hostname: ${record.exchange} - Priority: ${record.priority}`)
          .join(" | "),
      };
    }

    case "NS": {
      return {
        ok: dnsRes.some((record) => matchesRecord(record)),
        message: `Servers: ${dnsRes.join(" | ")}`,
      };
    }

    case "SOA": {
      return {
        ok: matchesRecord(dnsRes.nsname),
        message: `NS-Name: ${dnsRes.nsname} | Hostmaster: ${dnsRes.hostmaster} | Serial: ${dnsRes.serial} | Refresh: ${dnsRes.refresh} | Retry: ${dnsRes.retry} | Expire: ${dnsRes.expire} | MinTTL: ${dnsRes.minttl}`,
      };
    }

    case "SRV": {
      return {
        ok: dnsRes.some((record) => matchesRecord(record.name)),
        message: dnsRes
          .map((record) => `Name: ${record.name} | Port: ${record.port} | Priority: ${record.priority} | Weight: ${record.weight}`)
          .join(" | "),
      };
    }

    default:
      return { ok: false, message: `unsupported rrtype=${rrtype}` };
  }
}

(async () => {
  const monitor = parseMonitor();
  const hostname = String(monitor.hostname || "").trim();
  const rrtype = String(monitor.dns_resolve_type || "A").trim() || "A";
  const resolverPort = String(monitor.port || "53").trim() || "53";
  const conditions = parseConditions(monitor.conditions);

  if (!hostname) {
    throw new Error("hostname missing");
  }

  const resolverServers = await resolveResolverServers(monitor.dns_resolve_server);
  if (resolverServers.length === 0) {
    throw new Error("resolver server missing");
  }

  const dnsRes = await dnsResolve(hostname, resolverServers, resolverPort, rrtype);
  const outcome = buildDnsOutcome(rrtype, dnsRes, conditions);
  if (!outcome.ok) {
    throw new Error(outcome.message || "dns condition failed");
  }

  process.stdout.write(JSON.stringify({ ok: true, message: outcome.message }));
})().catch((error) => {
  process.stdout.write(JSON.stringify({
    ok: false,
    message: error && error.message ? error.message : String(error),
  }));
  process.exit(1);
});
NODE
  )"
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    DNS_LAST_PROBE_REASON="$(jq -r '.message // "ready"' <<< "$output" 2>/dev/null || printf 'ready')"
    DNS_LAST_PROBE_READY=1
    return 0
  fi

  DNS_LAST_PROBE_REASON="$(jq -r '.message // "dns=waiting"' <<< "$output" 2>/dev/null || printf 'dns=waiting')"
  DNS_LAST_PROBE_READY=0
  return 1
}

dns_monitor_is_ready() {
  local monitor_json="$1"
  probe_dns_monitor "$monitor_json"
}

container_http_blocking_reason() {
  local container_json="$1"
  local monitor_name url

  while IFS=$'\t' read -r monitor_name url; do
    [[ -n "$url" ]] || continue
    if ! probe_http_url "$url"; then
      printf 'monitor=%s url=%s reason=%s' "$monitor_name" "$url" "$HTTP_LAST_PROBE_REASON"
      return 0
    fi
  done < <(jq -r '.http_monitors[] | [.name, .url] | @tsv' <<< "$container_json")

  printf ''
}

unmapped_monitor_is_ready() {
  local monitor_json="$1"
  local monitor_type monitor_url

  monitor_type="$(jq -r '.type // ""' <<< "$monitor_json")"
  monitor_url="$(jq -r '.url // ""' <<< "$monitor_json")"

  case "$monitor_type" in
    http)
      [[ -n "$monitor_url" ]] || return 1
      http_url_is_ready "$monitor_url"
      ;;
    dns)
      dns_monitor_is_ready "$monitor_json"
      ;;
    *)
      return 1
      ;;
  esac
}

unmapped_monitor_blocking_reason() {
  local monitor_json="$1"
  local monitor_type monitor_url monitor_hostname monitor_resolver

  monitor_type="$(jq -r '.type // ""' <<< "$monitor_json")"
  monitor_url="$(jq -r '.url // ""' <<< "$monitor_json")"
  monitor_hostname="$(jq -r '.hostname // ""' <<< "$monitor_json")"
  monitor_resolver="$(jq -r '.dns_resolve_server // ""' <<< "$monitor_json")"

  case "$monitor_type" in
    http)
      if [[ -z "$monitor_url" ]]; then
        printf 'url missing'
        return 0
      fi
      if probe_http_url "$monitor_url"; then
        printf ''
      else
        printf 'url=%s reason=%s' "$monitor_url" "$HTTP_LAST_PROBE_REASON"
      fi
      ;;
    dns)
      if probe_dns_monitor "$monitor_json"; then
        printf ''
      else
        printf 'hostname=%s resolver=%s reason=%s' "$monitor_hostname" "$monitor_resolver" "$DNS_LAST_PROBE_REASON"
      fi
      ;;
    *)
      printf 'type=%s unsupported' "$monitor_type"
      ;;
  esac
}

sync_kuma_maintenance() {
  local maintenance_id="$1"
  local remaining_json="$2"
  local refresh_active_json="$3"
  local remaining_csv refresh_csv

  remaining_csv="$(json_array_join_csv "$remaining_json")"
  refresh_csv="$(json_array_join_csv "$refresh_active_json")"

  if ! run_kuma_socket_action_with_retry sync_bundle "$maintenance_id" "$remaining_csv" "$refresh_csv" >/dev/null; then
    announce "kuma: failed to sync maintenance id=${maintenance_id}"
    return 1
  fi

  return 0
}

resolve_kuma_maintenance_id() {
  local strategy escaped_title existing_id

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

  create_kuma_maintenance
}

ensure_kuma_maintenance() {
  local maintenance_id

  require_command docker || return 1
  require_command sqlite3 || return 1
  require_command jq || return 1

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

log_release_plan() {
  local release_plan_json="$1"
  local container_json

  while IFS= read -r container_json; do
    [[ -n "$container_json" ]] || continue
    announce_verbose "kuma: mapped container=$(jq -r '.name' <<< "$container_json") docker_ids=$(jq -r '.docker_monitor_ids | map(tostring) | join(",")' <<< "$container_json") http_ids=$(jq -r '.http_monitor_ids | map(tostring) | join(",")' <<< "$container_json") hosts=$(jq -r '.hosts | join(",")' <<< "$container_json")"
  done < <(jq -c '.containers[]' <<< "$release_plan_json")

  while IFS= read -r monitor_json; do
    [[ -n "$monitor_json" ]] || continue
    announce_verbose "kuma: unmapped monitor id=$(jq -r '.id' <<< "$monitor_json") type=$(jq -r '.type' <<< "$monitor_json") name=$(jq -r '.name' <<< "$monitor_json") url=$(jq -r '.url' <<< "$monitor_json") hostname=$(jq -r '.hostname // ""' <<< "$monitor_json") resolver=$(jq -r '.dns_resolve_server // ""' <<< "$monitor_json")"
  done < <(jq -c '.unmapped_monitors[]?' <<< "$release_plan_json")

  if ! json_array_is_empty "$(jq -c '.unmapped_monitor_ids' <<< "$release_plan_json")"; then
    announce_verbose "kuma: monitors without container mapping ids=$(jq -r '.unmapped_monitor_ids | map(tostring) | join(",")' <<< "$release_plan_json")"
  fi
}

start_action() {
  local maintenance_id monitors_json monitor_ids_json active_monitor_ids_json
  local monitor_ids active_monitor_ids monitor_count active_monitor_count

  maintenance_id="$(ensure_kuma_maintenance)" || return 1
  monitors_json="$(fetch_kuma_monitors_json)" || return 1
  monitor_ids_json="$(selected_monitor_ids_from_json "$monitors_json")"
  active_monitor_ids_json="$(active_monitor_ids_from_json "$monitors_json")"

  monitor_ids="$(json_array_join_csv "$monitor_ids_json")"
  active_monitor_ids="$(json_array_join_csv "$active_monitor_ids_json")"
  monitor_count="$(json_array_length "$monitor_ids_json")"
  active_monitor_count="$(json_array_length "$active_monitor_ids_json")"

  if [[ -z "$monitor_ids" ]]; then
    announce "kuma: no monitors returned by socket, skipping maintenance start"
    clear_state
    return 0
  fi

  if kuma_maintenance_is_active "$maintenance_id"; then
    announce "kuma: maintenance id=${maintenance_id} is already active, leaving it active"
    save_state "$maintenance_id" 0
    return 0
  fi

  announce "kuma: starting maintenance id=${maintenance_id} for all monitors count=${monitor_count} ids=${monitor_ids}"
  if ! run_kuma_socket_action_with_retry start_bundle "$maintenance_id" "$monitor_ids" "$active_monitor_ids" >/dev/null; then
    announce "kuma: failed to start maintenance id=${maintenance_id}"
    clear_state
    return 1
  fi

  if [[ -n "$active_monitor_ids" ]]; then
    announce "kuma: refreshed active monitors after maintenance start count=${active_monitor_count} ids=${active_monitor_ids}"
  else
    announce "kuma: no active monitors required heartbeat refresh after maintenance start"
  fi
  announce "kuma: maintenance id=${maintenance_id} is active"
  save_state "$maintenance_id" 1
}

stop_action() {
  local timeout_seconds poll_interval remaining_json release_plan_json pending_containers_json
  local active_monitor_ids_json unmapped_monitor_ids_json unmapped_monitors_json docker_containers_json monitor_json
  local status_json deadline_seconds released_container_names_json released_monitor_ids_json
  local released_active_monitor_ids_json new_pending_json container_json container_name
  local released_unmapped_names_json released_unmapped_ids_json new_unmapped_pending_json
  local unmapped_monitor_json unmapped_monitor_name
  local container_monitor_ids_json remaining_count blocking_reason
  local -A pending_container_reasons=()
  local -A pending_unmapped_reasons=()

  load_state

  if [[ -z "$STATE_MAINTENANCE_ID" ]]; then
    announce "kuma: no helper-owned maintenance state to stop"
    return 0
  fi

  if [[ "$STATE_STARTED_BY_SCRIPT" != "1" ]]; then
    announce "kuma: leaving maintenance id=${STATE_MAINTENANCE_ID} active because it was already active before backup"
    clear_state
    return 0
  fi

  if ! is_positive_integer "$STATE_MAINTENANCE_ID"; then
    announce "kuma: helper state contains an invalid maintenance id"
    clear_state
    return 1
  fi

  require_command curl || return 1

  monitor_json="$(fetch_kuma_monitors_json)" || return 1
  docker_containers_json="$(fetch_docker_containers_json)" || return 1
  release_plan_json="$(build_release_plan_json "$monitor_json" "$docker_containers_json")" || return 1
  remaining_json="$(jq -c '.selected_monitor_ids' <<< "$release_plan_json")"
  active_monitor_ids_json="$(jq -c '.active_monitor_ids' <<< "$release_plan_json")"
  pending_containers_json="$(jq -c '.containers' <<< "$release_plan_json")"
  unmapped_monitor_ids_json="$(jq -c '.unmapped_monitor_ids' <<< "$release_plan_json")"
  unmapped_monitors_json="$(jq -c '.unmapped_monitors' <<< "$release_plan_json")"
  timeout_seconds="$KUMA_POST_RUN_TIMEOUT_SECONDS"
  poll_interval="$KUMA_POST_RUN_POLL_INTERVAL_SECONDS"

  if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    timeout_seconds=600
  fi
  if ! [[ "$poll_interval" =~ ^[1-9][0-9]*$ ]]; then
    poll_interval=5
  fi

  log_release_plan "$release_plan_json"

  if ! kuma_maintenance_is_active "$STATE_MAINTENANCE_ID"; then
    announce "kuma: maintenance id=${STATE_MAINTENANCE_ID} is already inactive"
    if ! sync_kuma_maintenance "$STATE_MAINTENANCE_ID" '[]' '[]'; then
      announce "kuma: failed to clear inactive maintenance id=${STATE_MAINTENANCE_ID}"
      return 1
    fi
    clear_state
    return 0
  fi

  if json_array_is_empty "$remaining_json"; then
    announce "kuma: no selected monitors remain in maintenance, clearing helper state"
    if ! sync_kuma_maintenance "$STATE_MAINTENANCE_ID" '[]' '[]'; then
      announce "kuma: failed to clear maintenance id=${STATE_MAINTENANCE_ID}"
      return 1
    fi
    clear_state
    return 0
  fi

  announce "kuma: waiting for per-container readiness before clearing maintenance id=${STATE_MAINTENANCE_ID}"
  deadline_seconds=$((SECONDS + timeout_seconds))

  while true; do
    status_json="$(fetch_docker_container_status_json)" || return 1
    released_container_names_json='[]'
    released_monitor_ids_json='[]'
    released_active_monitor_ids_json='[]'
    new_pending_json='[]'
    released_unmapped_names_json='[]'
    released_unmapped_ids_json='[]'
    new_unmapped_pending_json='[]'

    while IFS= read -r container_json; do
      [[ -n "$container_json" ]] || continue
      container_name="$(jq -r '.name' <<< "$container_json")"
      container_monitor_ids_json="$(jq -c '.monitor_ids' <<< "$container_json")"
      blocking_reason="$(container_status_blocking_reason "$container_name" "$status_json")"

      if [[ -z "$blocking_reason" ]]; then
        blocking_reason="$(container_http_blocking_reason "$container_json")"
      fi

      if [[ -z "$blocking_reason" ]]; then
        released_container_names_json="$(jq -cn \
          --argjson existing "$released_container_names_json" \
          --arg name "$container_name" \
          '$existing + [$name] | unique | sort')"
        released_monitor_ids_json="$(jq -cn \
          --argjson existing "$released_monitor_ids_json" \
          --argjson current "$container_monitor_ids_json" \
          '$existing + $current | unique | sort')"
        released_active_monitor_ids_json="$(jq -cn \
          --argjson existing "$released_active_monitor_ids_json" \
          --argjson current "$(json_array_intersection "$container_monitor_ids_json" "$active_monitor_ids_json")" \
          '$existing + $current | unique | sort')"
        unset 'pending_container_reasons[$container_name]'
      else
        new_pending_json="$(jq -cn \
          --argjson existing "$new_pending_json" \
          --argjson current "$container_json" \
          '$existing + [$current]')"
        if [[ "${pending_container_reasons[$container_name]:-}" != "$blocking_reason" ]]; then
          announce "kuma: waiting for container=${container_name} reason=${blocking_reason}"
          pending_container_reasons[$container_name]="$blocking_reason"
        fi
      fi
    done < <(jq -c '.[]' <<< "$pending_containers_json")

    while IFS= read -r unmapped_monitor_json; do
      [[ -n "$unmapped_monitor_json" ]] || continue
      if unmapped_monitor_is_ready "$unmapped_monitor_json"; then
        unmapped_monitor_name="$(jq -r '.name' <<< "$unmapped_monitor_json")"
        released_unmapped_names_json="$(jq -cn \
          --argjson existing "$released_unmapped_names_json" \
          --arg name "$unmapped_monitor_name" \
          '$existing + [$name] | unique | sort')"
        released_unmapped_ids_json="$(jq -cn \
          --argjson existing "$released_unmapped_ids_json" \
          --argjson current "$(jq -c '[.id]' <<< "$unmapped_monitor_json")" \
          '$existing + $current | unique | sort')"
        unset 'pending_unmapped_reasons[$unmapped_monitor_name]'
      else
        new_unmapped_pending_json="$(jq -cn \
          --argjson existing "$new_unmapped_pending_json" \
          --argjson current "$unmapped_monitor_json" \
          '$existing + [$current]')"
        unmapped_monitor_name="$(jq -r '.name' <<< "$unmapped_monitor_json")"
        blocking_reason="$(unmapped_monitor_blocking_reason "$unmapped_monitor_json")"
        if [[ "${pending_unmapped_reasons[$unmapped_monitor_name]:-}" != "$blocking_reason" ]]; then
          announce "kuma: waiting for unmapped monitor=${unmapped_monitor_name} reason=${blocking_reason}"
          pending_unmapped_reasons[$unmapped_monitor_name]="$blocking_reason"
        fi
      fi
    done < <(jq -c '.[]' <<< "$unmapped_monitors_json")

    if ! json_array_is_empty "$released_unmapped_ids_json"; then
      released_monitor_ids_json="$(jq -cn \
        --argjson existing "$released_monitor_ids_json" \
        --argjson current "$released_unmapped_ids_json" \
        '$existing + $current | unique | sort')"
      released_active_monitor_ids_json="$(jq -cn \
        --argjson existing "$released_active_monitor_ids_json" \
        --argjson current "$(json_array_intersection "$released_unmapped_ids_json" "$active_monitor_ids_json")" \
        '$existing + $current | unique | sort')"
    fi

    if ! json_array_is_empty "$released_monitor_ids_json"; then
      remaining_json="$(json_array_diff "$remaining_json" "$released_monitor_ids_json")"
      pending_containers_json="$new_pending_json"
      unmapped_monitors_json="$new_unmapped_pending_json"

      while IFS= read -r container_name; do
        [[ -n "$container_name" ]] || continue
        announce "kuma: releasing monitors for container=${container_name}"
      done < <(jq -r '.[]' <<< "$released_container_names_json")

      while IFS= read -r unmapped_monitor_name; do
        [[ -n "$unmapped_monitor_name" ]] || continue
        announce "kuma: releasing unmapped monitor=${unmapped_monitor_name}"
      done < <(jq -r '.[]' <<< "$released_unmapped_names_json")

      if ! sync_kuma_maintenance "$STATE_MAINTENANCE_ID" "$remaining_json" "$released_active_monitor_ids_json"; then
        return 1
      fi
    else
      pending_containers_json="$new_pending_json"
      unmapped_monitors_json="$new_unmapped_pending_json"
    fi

    remaining_count="$(json_array_length "$remaining_json")"
    if [[ "$remaining_count" == "0" ]]; then
      announce "kuma: maintenance id=${STATE_MAINTENANCE_ID} is inactive"
      clear_state
      return 0
    fi

    if (( SECONDS >= deadline_seconds )); then
      announce "kuma: timeout reached while waiting for readiness, leaving maintenance id=${STATE_MAINTENANCE_ID} active for remaining monitor ids=$(json_array_join_csv "$remaining_json")"
      if ! json_array_is_empty "$pending_containers_json"; then
        announce "kuma: containers still not ready=$(jq -r '[.[].name] | join(\",\")' <<< "$pending_containers_json")"
      fi
      if ! json_array_is_empty "$unmapped_monitors_json"; then
        announce "kuma: unmapped monitors still in maintenance ids=$(jq -r 'map(.id) | join(\",\")' <<< "$unmapped_monitors_json") names=$(jq -r 'map(.name) | join(\",\")' <<< "$unmapped_monitors_json")"
      elif ! json_array_is_empty "$unmapped_monitor_ids_json"; then
        announce "kuma: unmapped monitors still in maintenance ids=$(json_array_join_csv "$unmapped_monitor_ids_json")"
      fi
      return 0
    fi

    sleep "$poll_interval"
  done
}

main() {
  local action="${1:-}"

  reset_log_if_needed

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
