#!/usr/bin/env bash
# Shared Radarr API access for the scripts in this directory.
#
# Both scripts run as Radarr custom scripts, so they run inside the Radarr
# container and `/config/config.xml` is right there. Reading the API key from it
# is what keeps this bundle free of secrets: nothing has to be templated into a
# compose environment, nothing lands in the repository, and a key rotated in the
# UI is picked up on the next invocation with no redeploy.
#
# Sourced, never executed.

RADARR_CONFIG="${RADARR_CONFIG:-/config/config.xml}"

log() { printf '[%s] %s\n' "${LOG_TAG:-radarr}" "$*"; }

# One tag's text content. The file is machine-written by Radarr and every value
# used here sits on its own line, so a line-oriented read is exact rather than a
# gamble on XML shape.
config_value() {
    sed -n "s#.*<$1>\(.*\)</$1>.*#\1#p" "$RADARR_CONFIG" | head -n 1
}

radarr_api_init() {
    [ -r "$RADARR_CONFIG" ] || { log "cannot read $RADARR_CONFIG"; return 1; }

    RADARR_API_KEY="$(config_value ApiKey)"
    [ -n "$RADARR_API_KEY" ] || { log "no ApiKey in $RADARR_CONFIG"; return 1; }

    local port url_base
    port="$(config_value Port)"
    url_base="$(config_value UrlBase)"
    # 127.0.0.1 rather than the container name or the LAN address: the call never
    # leaves the container, so it works regardless of network or reverse proxy.
    RADARR_URL="${RADARR_URL:-http://127.0.0.1:${port:-7878}${url_base}}"
}

# api <METHOD> <PATH> [curl args...]
api() {
    local method="$1" path="$2"
    shift 2
    "${CURL:-curl}" -sS -m 30 -X "$method" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        "$@" "${RADARR_URL}${path}"
}

# Radarr's own uri encoding, via jq, because the container ships no python3.
uri_encode() { "${JQ:-jq}" -rn --arg v "$1" '$v|@uri'; }
