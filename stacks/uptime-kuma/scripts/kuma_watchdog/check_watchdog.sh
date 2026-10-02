#!/usr/bin/env bash
# Covers the resend logic: a fresh finding posts, an already-posted one stays
# silent, and one older than the resend interval posts again.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

export WATCHDOG_SOURCE_ONLY=1
export DISCORD_WEBHOOK_URL="https://example.invalid/webhook"
export LOG_FILE="${WORK_DIR}/watchdog.log"
export STATE_FILE="${WORK_DIR}/watchdog.state"
export VERBOSE_OUTPUT=0
export RESEND_HOURS=24

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/kuma_watchdog.sh"

FINDINGS='[{"key":"monitor-no-notification:1","text":"monitor 1 has no notification"}]'

collect_findings_json() {
  printf '%s' "$FINDINGS"
}

# Neither docker nor curl is touched by this check, so their presence is not a
# precondition for running it.
require_command() {
  command -v jq >/dev/null 2>&1
}

POSTED_FILE="${WORK_DIR}/posted"
# One marker per post, not the message itself: the message is multi-line, so
# counting its lines would count wrong.
post_to_discord() {
  printf 'post\n' >> "$POSTED_FILE"
  return 0
}

posted_count() {
  [[ -f "$POSTED_FILE" ]] || { printf '0'; return; }
  wc -l < "$POSTED_FILE" | tr -d ' '
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

main >/dev/null || fail "first run returned non-zero"
[[ "$(posted_count)" == "1" ]] || fail "a new finding must be posted"

main >/dev/null || fail "second run returned non-zero"
[[ "$(posted_count)" == "1" ]] || fail "a finding inside the resend window must stay silent"

# Age the recorded post past the resend interval.
printf 'monitor-no-notification:1\t%s\n' "$(( $(date +%s) - 25 * 3600 ))" > "$STATE_FILE"

main >/dev/null || fail "third run returned non-zero"
[[ "$(posted_count)" == "2" ]] || fail "a finding older than the resend interval must be posted again"

FINDINGS='[]'
main >/dev/null || fail "empty run returned non-zero"
[[ "$(posted_count)" == "2" ]] || fail "an empty findings list must post nothing"
[[ ! -s "$STATE_FILE" ]] || fail "a cleared finding must fall out of the state file"

printf 'OK\n'
