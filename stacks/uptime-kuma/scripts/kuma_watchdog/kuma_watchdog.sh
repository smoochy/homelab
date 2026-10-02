#!/usr/bin/env bash
# Reports Uptime Kuma configuration faults that make Kuma itself go quiet:
# monitors with no notification attached, and maintenance windows that have
# been suppressing alerts for too long. Posts straight to Discord, never
# through Kuma, because a Kuma that has gone quiet cannot report that it has.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

load_env_file() {
  local env_file="${SCRIPT_DIR}/.env"
  [[ -f "$env_file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

load_env_file

# User settings: override these via .env in the same directory.
KUMA_CONTAINER_NAME="${KUMA_CONTAINER_NAME:-uptime-kuma}"     # Uptime Kuma container name for docker exec based control.
KUMA_BASE_URL="${KUMA_BASE_URL:-http://127.0.0.1:3001}"       # Uptime Kuma URL as seen from inside the container.
KUMA_AUTH_TOKEN="${KUMA_AUTH_TOKEN:-}"                        # Preferred auth method when available.
KUMA_USERNAME="${KUMA_USERNAME:-}"                            # Kuma username when not using an auth token.
KUMA_PASSWORD="${KUMA_PASSWORD:-}"                            # Kuma password when not using an auth token.
KUMA_SOCKET_TIMEOUT_MS="${KUMA_SOCKET_TIMEOUT_MS:-20000}"     # Timeout in milliseconds for Kuma socket connect/login/action acks.
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"                # Discord webhook the findings are posted to.
MAINTENANCE_MAX_HOURS="${MAINTENANCE_MAX_HOURS:-6}"           # Report a window that has been suppressing alerts for longer than this.
RESEND_HOURS="${RESEND_HOURS:-24}"                            # Repeat a finding this often while the condition holds.
INCLUDE_PAUSED_MONITORS="${INCLUDE_PAUSED_MONITORS:-0}"       # Set to 1 to also report paused monitors without a notification.

LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/kuma_watchdog.log}"
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/kuma_watchdog.state}"
VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-1}"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG_FILE"
}

announce() {
  log "$1"
  if [[ "$VERBOSE_OUTPUT" != "0" ]]; then
    printf '%s\n' "$1"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    announce "watchdog: required command '$1' is missing"
    return 1
  fi
}

# Asks Kuma itself rather than reading kuma.db. Kuma derives a window's status
# from its dates at call time, and the host-side view of the maintenance table
# lags behind the container's writes, so the socket is the only honest source.
collect_findings_json() {
  docker exec -i \
    -e KUMA_URL="$KUMA_BASE_URL" \
    -e KUMA_AUTH_TOKEN="$KUMA_AUTH_TOKEN" \
    -e KUMA_USERNAME="$KUMA_USERNAME" \
    -e KUMA_PASSWORD="$KUMA_PASSWORD" \
    -e KUMA_SOCKET_TIMEOUT_MS="$KUMA_SOCKET_TIMEOUT_MS" \
    -e MAINTENANCE_MAX_HOURS="$MAINTENANCE_MAX_HOURS" \
    -e INCLUDE_PAUSED_MONITORS="$INCLUDE_PAUSED_MONITORS" \
    "$KUMA_CONTAINER_NAME" \
    node - <<'NODE'
const { io } = require("socket.io-client");

const url = process.env.KUMA_URL || "http://127.0.0.1:3001";
const authToken = process.env.KUMA_AUTH_TOKEN || "";
const username = process.env.KUMA_USERNAME || "";
const password = process.env.KUMA_PASSWORD || "";
const socketTimeout = Number.parseInt(process.env.KUMA_SOCKET_TIMEOUT_MS || "20000", 10);
const maxHours = Number.parseFloat(process.env.MAINTENANCE_MAX_HOURS || "6");
const includePaused = (process.env.INCLUDE_PAUSED_MONITORS || "0") === "1";

function emitAck(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    let done = false;
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        reject(new Error(`${event} timed out`));
      }
    }, socketTimeout);
    socket.emit(event, ...args, (response) => {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      if (!response || response.ok !== true) {
        reject(new Error(response && response.msg ? response.msg : `${event} failed`));
        return;
      }
      resolve(response);
    });
  });
}

function once(socket, event) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${event} timed out`)), socketTimeout);
    socket.once(event, (payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

function connectSocket() {
  return new Promise((resolve, reject) => {
    const socket = io(url, { transports: ["websocket"], reconnection: false });
    const timer = setTimeout(() => reject(new Error("connect timed out")), socketTimeout);
    socket.once("connect", () => {
      clearTimeout(timer);
      resolve(socket);
    });
    socket.once("connect_error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

// "YYYY-MM-DD HH:mm:ss" in the server's own timezone, which is what Kuma
// hands back for a window created with timezoneOption SAME_AS_SERVER. Parsing
// it as local time is correct because this runs inside that same container.
function parseLocalStamp(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(value || "");
  if (!match) {
    return null;
  }
  return new Date(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6])
  );
}

(async () => {
  const socket = await connectSocket();
  const findings = [];

  try {
    if (authToken) {
      await emitAck(socket, "loginByToken", authToken);
    } else {
      await emitAck(socket, "login", { username, password });
    }

    const maintenancePromise = once(socket, "maintenanceList");
    await emitAck(socket, "getMaintenanceList");
    const maintenanceList = await maintenancePromise;

    const now = Date.now();
    for (const maintenance of Object.values(maintenanceList || {})) {
      if (maintenance.status !== "under-maintenance") {
        continue;
      }

      const start = parseLocalStamp((maintenance.dateRange || [])[0]);
      const end = parseLocalStamp((maintenance.dateRange || [])[1]);

      if (!end) {
        // No end date means nothing will ever lift it. That is the failure
        // mode this watchdog exists for, so it is reported without waiting.
        findings.push({
          key: `maintenance-no-end:${maintenance.id}`,
          text: `Maintenance "${maintenance.title}" (id ${maintenance.id}, strategy ${maintenance.strategy}) is suppressing alerts and has no end date, so it will never lift on its own.`,
        });
        continue;
      }

      const runningHours = start ? (now - start.getTime()) / 3600000 : null;
      if (runningHours !== null && runningHours > maxHours) {
        findings.push({
          key: `maintenance-too-long:${maintenance.id}`,
          text: `Maintenance "${maintenance.title}" (id ${maintenance.id}) has been suppressing alerts for ${runningHours.toFixed(1)} hours, ends ${(maintenance.dateRange || [])[1]}.`,
        });
      }
    }

    const monitorPromise = once(socket, "monitorList");
    await emitAck(socket, "getMonitorList");
    const monitorList = await monitorPromise;

    for (const monitor of Object.values(monitorList || {})) {
      if (!includePaused && monitor.active !== true) {
        continue;
      }

      const notificationIds = monitor.notificationIDList || {};
      const attached = Object.keys(notificationIds).filter((id) => notificationIds[id]);
      if (attached.length === 0) {
        findings.push({
          key: `monitor-no-notification:${monitor.id}`,
          text: `Monitor "${monitor.name}" (id ${monitor.id}) has no notification attached, so it can go down without telling anyone.`,
        });
      }
    }
  } finally {
    socket.close();
  }

  process.stdout.write(JSON.stringify(findings));
})().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
NODE
}

post_to_discord() {
  local message="$1"
  local payload

  payload="$(jq -nc --arg content "$message" '{content: $content}')"
  if ! curl -sS -f -X POST -H 'Content-Type: application/json' -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null; then
    announce "watchdog: failed to post to Discord"
    return 1
  fi

  return 0
}

main() {
  local findings_json now resend_seconds due_json message
  local new_state=""

  require_command docker || return 1
  require_command jq || return 1
  require_command curl || return 1

  if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    announce "watchdog: DISCORD_WEBHOOK_URL is not set"
    return 1
  fi

  if ! findings_json="$(collect_findings_json 2>>"$LOG_FILE")"; then
    announce "watchdog: failed to collect findings from Kuma"
    return 1
  fi

  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$findings_json"; then
    announce "watchdog: Kuma returned an unusable findings payload"
    return 1
  fi

  now="$(date +%s)"
  resend_seconds=$(( ${RESEND_HOURS%.*} * 3600 ))
  if (( resend_seconds <= 0 )); then
    resend_seconds=86400
  fi

  # A finding is posted when it is new, or when the last post for it is older
  # than the resend interval. Findings that have gone away simply fall out of
  # the state file, so the next occurrence is reported as new again.
  due_json='[]'
  while IFS=$'\t' read -r key text; do
    [[ -n "$key" ]] || continue
    local last_sent=0
    if [[ -f "$STATE_FILE" ]]; then
      last_sent="$(awk -F '\t' -v k="$key" '$1 == k { print $2; exit }' "$STATE_FILE")"
      [[ "$last_sent" =~ ^[0-9]+$ ]] || last_sent=0
    fi

    if (( now - last_sent >= resend_seconds )); then
      due_json="$(jq -c --arg text "$text" '. + [$text]' <<< "$due_json")"
      new_state+="${key}"$'\t'"${now}"$'\n'
    else
      new_state+="${key}"$'\t'"${last_sent}"$'\n'
    fi
  done < <(jq -r '.[] | [.key, .text] | @tsv' <<< "$findings_json")

  if [[ "$due_json" == "[]" ]]; then
    announce "watchdog: $(jq 'length' <<< "$findings_json") finding(s), none due for a Discord post"
  else
    message="$(jq -r '"**Uptime Kuma watchdog**\n" + (map("- " + .) | join("\n"))' <<< "$due_json")"
    if ! post_to_discord "$message"; then
      return 1
    fi
    announce "watchdog: posted $(jq 'length' <<< "$due_json") finding(s) to Discord"
  fi

  # Written only after a successful run, so a failed post is retried next time
  # instead of being silently marked as delivered.
  printf '%s' "$new_state" > "$STATE_FILE"
  return 0
}

# The check script sources this file to exercise the resend logic against a
# fixed findings payload, so it needs the functions without the run.
if [[ "${WATCHDOG_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
