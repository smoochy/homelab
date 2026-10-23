#!/bin/sh
# Proton WireGuard profile renewer (homelab #5038, map #4863).
#
# One duty: keep the persistent WireGuard profiles of the Proton account alive by renewing them in place before they expire. `--renew-serial` reuses the private key (proven live on 2026-10-18), so the keys in the other stacks' `.env.enc` never change and nothing else is touched: no write-back, no pull request, no consumer redeploy. If a renewal ever does change a key, this rider alerts and rewrites nothing.
#
# Each tick lists the account's persistent configs, renews every one with LEAD_DAYS or less remaining, and touches the heartbeat only when the whole tick succeeded. The listing authenticates, and confgen refreshes the saved session by itself once less than 7 days remain, so a daily tick keeps the 30 day Proton session alive without a separate refresh job.

set -u

LEAD_DAYS="${RENEW_LEAD_DAYS:-14}"
INTERVAL="${RENEW_INTERVAL_SECONDS:-86400}"
# After a failed tick the next try comes sooner than the daily one, so a transient Proton error does not cost a day of the lead window. Terminal failures (below) ignore it.
RETRY_INTERVAL="${RENEW_RETRY_SECONDS:-3600}"
CONFGEN="${CONFGEN_BIN:-protonvpn-wg}"
HEARTBEAT="${RENEWER_HEARTBEAT:-/run/proton-renewer.heartbeat}"
APPRISE_ENDPOINT="${APPRISE_ENDPOINT:-}"
# Serials the operator declares free of any use. Only these are ever revoked, and only on error 2028; empty means alert only. The rider cannot see which keys the stacks hold, so it never decides this itself.
REVOKE_ALLOWED_SERIALS="${REVOKE_ALLOWED_SERIALS:-}"
PROTON_USERNAME="${PROTON_USERNAME:-}"
PROTON_PASSWORD="${PROTON_PASSWORD:-}"

log() {
    # $1 level, $2 message
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2"
}

# Apprise, or silence where no endpoint is configured. The title and body are built from serials, device names and numbers of Proton's making, so jq does the quoting.
notify() {
    # $1 title, $2 body, $3 type
    [ -n "$APPRISE_ENDPOINT" ] || return 0
    _payload="$(jq -nc --arg t "$1" --arg b "$2" --arg y "$3" '{title:$t,body:$b,type:$y,format:"markdown"}')"
    wget -q -O /dev/null --timeout=10 \
        --header='Content-Type: application/json' \
        --post-data="$_payload" \
        "$APPRISE_ENDPOINT" && return 0
    log warn "apprise notify failed: $1"
}

# Runs confgen with the password on stdin, so it never reaches ps or the environment of the child. Output goes to $OUT, the exit code is returned.
confgen() {
    printf '%s' "$PROTON_PASSWORD" | "$CONFGEN" --username "$PROTON_USERNAME" --password-stdin "$@" >"$OUT" 2>"$ERR"
}

# Classifies the last failure from confgen's own text. Prints one of: bad_password, captcha, too_many, other.
classify() {
    _text="$(cat "$OUT" "$ERR" 2>/dev/null)"
    case "$_text" in
        *8002*) echo bad_password ;;
        *9001*) echo captcha ;;
        *2028*) echo too_many ;;
        *) echo other ;;
    esac
}

# Terminal failures wait for a human, so the loop stops calling Proton: a retry cannot fix a wrong password and only risks a lockout, and every retry of a CAPTCHA mints a fresh challenge. A container restart clears the halt once the cause is fixed.
HALTED=""

fail_tick() {
    # $1 class, $2 context
    case "$1" in
        bad_password)
            HALTED=1
            notify "Proton renewer stopped" "Wrong Proton password (code 8002). Fix PROTON_PASSWORD in the stack .env.enc and restart the container. No retry until then." failure
            ;;
        captcha)
            HALTED=1
            _url="$(grep -o 'https://[^ ]*captcha[^ ]*' "$OUT" "$ERR" 2>/dev/null | head -n 1 | cut -d: -f2-)"
            notify "Proton renewer needs a CAPTCHA" "Proton asks for human verification (code 9001). Solve ${_url:-the challenge from the container log}, set PROTONVPN_HV_TOKEN, restart the container." failure
            ;;
        *)
            notify "Proton renewer failed" "$2 failed (see container log)." failure
            ;;
    esac
    log error "$2 failed: $1"
}

# Prints the persistent configs as JSON, or returns 1.
list_configs() {
    confgen --list-configs --json || return 1
    jq -e 'type == "array"' "$OUT" >/dev/null 2>&1
}

# Revokes one serial, only if the operator allowed it.
revoke_if_allowed() {
    # $1 serial
    case " $(echo "$REVOKE_ALLOWED_SERIALS" | tr ',' ' ') " in
        *" $1 "*) ;;
        *) return 1 ;;
    esac
    confgen --revoke-serial "$1" || return 1
    log warn "revoked allowed serial $1 after error 2028"
}

# One renewal. Returns 0 on success, 1 on failure.
renew_one() {
    # $1 serial, $2 device name, $3 fingerprint
    if ! confgen --renew-serial "$1"; then
        _class="$(classify)"
        if [ "$_class" = too_many ]; then
            # Revoking is the fallback for the account cap, never the first move, and only for serials the operator released.
            _rest="$(echo "$REVOKE_ALLOWED_SERIALS" | tr ',' ' ')"
            for _s in $_rest; do
                if revoke_if_allowed "$_s" && confgen --renew-serial "$1"; then
                    _class=ok
                    break
                fi
            done
        fi
        if [ "$_class" != ok ]; then
            fail_tick "$_class" "renewal of $2 ($1)"
            return 1
        fi
    fi
    log info "renewed $2: $(grep -h -E 'Certificate renewed|New expiry' "$OUT" | tr '\n' ' ')"
    # The key must be unchanged. The serial changed, so find the profile again by its device name.
    list_configs || { fail_tick other "re-listing after renewing $2"; return 1; }
    _after="$(jq -r --arg d "$2" '[.[] | select(.device_name == $d)][0].fingerprint // ""' "$OUT")"
    if [ "$_after" != "$3" ]; then
        notify "Proton renewer: key changed" "Renewing $2 changed its key (fingerprint \"$3\" -> \"$_after\"). The stacks hold the old key. Nothing was rewritten; update the .env.enc files by hand." failure
        log error "fingerprint of $2 changed after renewal"
        return 1
    fi
    return 0
}

# One tick. Returns 0 when the check and every due renewal succeeded.
tick() {
    OUT="$(mktemp)"
    ERR="$(mktemp)"
    trap 'rm -f "$OUT" "$ERR"' EXIT
    if ! list_configs; then
        fail_tick "$(classify)" "listing configs"
        return 1
    fi
    _total="$(jq 'length' "$OUT")"
    # Fractional seconds are cut because fromdateiso8601 does not take them.
    # confgen cannot renew a profile without a device name ("certificate N has no device name"), so such a profile is reported and skipped; failing it every tick would keep the heartbeat stale for ever.
    for _s in $(jq -r --argjson lead "$LEAD_DAYS" '.[] | select(.device_name == "" and ((.expires | sub("\\.[0-9]+"; "") | fromdateiso8601) - now <= $lead * 86400)) | .serial' "$OUT"); do
        log warn "profile $_s has no device name and cannot be renewed; replace it before it expires"
    done
    _due="$(jq -r --argjson lead "$LEAD_DAYS" '
        .[] | select(.device_name != "" and ((.expires | sub("\\.[0-9]+"; "") | fromdateiso8601) - now <= $lead * 86400))
        | [.serial, .device_name, .fingerprint] | @tsv' "$OUT")"
    log info "checked $_total persistent configs, lead ${LEAD_DAYS}d"
    _ok=0
    if [ -n "$_due" ]; then
        # Serialized on purpose: the API documents no rate limit, so one call at a time is the cautious reading.
        # Read from a file, not a pipe: a pipe would run the loop in a subshell and lose HALTED.
        _dues="$(mktemp)"
        printf '%s\n' "$_due" >"$_dues"
        while IFS="$(printf '\t')" read -r _serial _device _fp; do
            renew_one "$_serial" "$_device" "$_fp" || _ok=1
            [ -z "$HALTED" ] || break
        done <"$_dues"
        rm -f "$_dues"
    fi
    rm -f "$OUT" "$ERR"
    trap - EXIT
    return "$_ok"
}

main() {
    if [ -z "$PROTON_USERNAME" ] || [ -z "$PROTON_PASSWORD" ]; then
        log error "PROTON_USERNAME and PROTON_PASSWORD are required"
        exit 1
    fi
    while :; do
        if [ -n "$HALTED" ]; then
            sleep "$INTERVAL"
            continue
        fi
        if tick; then
            : >"$HEARTBEAT"
            _wait="$INTERVAL"
        else
            _wait="$RETRY_INTERVAL"
        fi
        [ -z "${RENEWER_ONCE:-}" ] || return 0
        sleep "$_wait"
    done
}

# Sourced by the tests; run only when executed.
if [ -z "${RENEWER_SOURCED:-}" ]; then
    main
fi
