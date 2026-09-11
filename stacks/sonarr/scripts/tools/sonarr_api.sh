#!/usr/bin/env bash
# Shared Sonarr API access for the scripts in this directory.
#
# Both scripts run as Sonarr custom scripts, so they run inside the Sonarr
# container and `/config/config.xml` is right there. Reading the API key from it
# is what keeps this bundle free of secrets: nothing has to be templated into a
# compose environment, nothing lands in the repository, and a key rotated in the
# UI is picked up on the next invocation with no redeploy.
#
# Sourced, never executed. The Radarr counterpart under `stacks/radarr` is a
# deliberate copy rather than a shared file: the two containers mount only their
# own `/config`, so neither can read a file that lives in the other's appdata.

SONARR_CONFIG="${SONARR_CONFIG:-/config/config.xml}"

log() { printf '[%s] %s\n' "${LOG_TAG:-sonarr}" "$*"; }

# One tag's text content. The file is machine-written by Sonarr and every value
# used here sits on its own line, so a line-oriented read is exact rather than a
# gamble on XML shape.
config_value() {
    sed -n "s#.*<$1>\(.*\)</$1>.*#\1#p" "$SONARR_CONFIG" | head -n 1
}

sonarr_api_init() {
    [ -r "$SONARR_CONFIG" ] || { log "cannot read $SONARR_CONFIG"; return 1; }

    SONARR_API_KEY="$(config_value ApiKey)"
    [ -n "$SONARR_API_KEY" ] || { log "no ApiKey in $SONARR_CONFIG"; return 1; }

    local port url_base
    port="$(config_value Port)"
    url_base="$(config_value UrlBase)"
    # 127.0.0.1 rather than the container name or the LAN address: the call never
    # leaves the container, so it works regardless of network or reverse proxy.
    SONARR_URL="${SONARR_URL:-http://127.0.0.1:${port:-8989}${url_base}}"
}

# api <METHOD> <PATH> [curl args...]
api() {
    local method="$1" path="$2"
    shift 2
    "${CURL:-curl}" -sS -m 30 -X "$method" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        "$@" "${SONARR_URL}${path}"
}

# Sonarr's own uri encoding, via jq, because the container ships no python3.
uri_encode() { "${JQ:-jq}" -rn --arg v "$1" '$v|@uri'; }
