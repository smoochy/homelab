#!/bin/sh
# self-check-inputs: stacks/proton-renewer/renewer/
# Tests for renewer.sh against a fake confgen binary and a fake wget. Run: sh stacks/proton-renewer/renewer/tests/test_renewer.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RENEWER="$HERE/../renewer.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0

mkdir -p "$T/bin"
# Fake confgen: serves $T/configs.json, records every call in $T/calls. FAKE_FAIL_RENEW=<code> makes renewals fail with that Proton code, FAKE_FAIL_LIST=<code> makes the listing fail, FAKE_CHANGE_KEY=1 makes a renewal change the fingerprint.
cat >"$T/bin/protonvpn-wg" <<'EOF'
#!/bin/sh
echo "$*" >>"$T/calls"
cat >/dev/null
case "$*" in
    *--list-configs*)
        if [ -n "${FAKE_FAIL_LIST:-}" ]; then echo "Error: authentication failed: code $FAKE_FAIL_LIST" >&2; exit 1; fi
        cat "$T/configs.json" ;;
    *--renew-serial*)
        if [ -n "${FAKE_FAIL_RENEW:-}" ] && [ ! -f "$T/revoked" ]; then echo "Error: certificate error (code $FAKE_FAIL_RENEW)" >&2; exit 1; fi
        serial="$(echo "$*" | sed 's/.*--renew-serial \([^ ]*\).*/\1/')"
        fp=""; [ -z "${FAKE_CHANGE_KEY:-}" ] || fp="changed"
        jq --arg s "$serial" --arg f "$fp" --arg e "$(date -u -d '+365 days' +%Y-%m-%dT%H:%M:%SZ)" \
            'map(if .serial == $s then .serial = ($s + "n") | .expires = $e | .fingerprint = (if $f == "" then .fingerprint else $f end) else . end)' \
            "$T/configs.json" >"$T/configs.new" && mv "$T/configs.new" "$T/configs.json"
        echo "Certificate renewed: $serial -> ${serial}n" ;;
    *--revoke-serial*) touch "$T/revoked"; echo "revoked" ;;
esac
EOF
cat >"$T/bin/wget" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in --post-data=*) echo "${a#--post-data=}" >>"$T/notified" ;; esac; done
EOF
chmod +x "$T/bin/protonvpn-wg" "$T/bin/wget"

days() { date -u -d "+$1 days" +%Y-%m-%dT%H:%M:%SZ; }

# $1 name; env of the case is passed by the caller. Resets state, then runs one tick.
run_once() {
    rm -f "$T/calls" "$T/notified" "$T/revoked" "$T/hb"
    PATH="$T/bin:$PATH" T="$T" RENEWER_ONCE=1 RENEWER_HEARTBEAT="$T/hb" \
        PROTON_USERNAME=u PROTON_PASSWORD=secret-pw APPRISE_ENDPOINT=http://apprise.invalid/n \
        RENEW_RETRY_SECONDS=0 RENEW_INTERVAL_SECONDS=0 \
        sh "$RENEWER" >"$T/log" 2>&1
}

check() {
    # $1 description, $2 condition command
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi
}

two_configs() {
    printf '[{"serial":"A","mode":"persistent","device_name":"dev-a","expires":"%s","fingerprint":"fa"},{"serial":"B","mode":"persistent","device_name":"dev-b","expires":"%s","fingerprint":"fb"}]' "$(days "$1")" "$(days "$2")" >"$T/configs.json"
}

# 1. Nothing due: no renewal, heartbeat touched, no alert.
two_configs 100 200
run_once
check "nothing due: no renew call" '! grep -q renew-serial "$T/calls"'
check "nothing due: heartbeat touched" '[ -f "$T/hb" ]'
check "nothing due: silent" '[ ! -f "$T/notified" ]'

# 2. One due (10d <= 14d): only that one renews, key unchanged, heartbeat touched.
two_configs 10 200
run_once
check "due: renews A" 'grep -q -- "--renew-serial A" "$T/calls"'
check "due: leaves B alone" '! grep -q -- "--renew-serial B" "$T/calls"'
check "due: heartbeat touched" '[ -f "$T/hb" ]'
check "due: password never on the command line" '! grep -q secret-pw "$T/calls"'

# 2b. A due profile without a device name is skipped with a warning and does not fail the tick.
printf '[{"serial":"N","mode":"persistent","device_name":"","expires":"%s","fingerprint":"fn"}]' "$(days 10)" >"$T/configs.json"
run_once
check "no device name: not renewed" '! grep -q renew-serial "$T/calls"'
check "no device name: warned" 'grep -q "no device name" "$T/log"'
check "no device name: heartbeat touched" '[ -f "$T/hb" ]'

# 3. Lead time is an env value: 5d lead leaves a 10d profile alone.
two_configs 10 200
RENEW_LEAD_DAYS=5 run_once
check "lead 5d: nothing renewed" '! grep -q renew-serial "$T/calls"'

# 4. A renewal that changes the key alerts and does not touch the heartbeat.
two_configs 10 200
FAKE_CHANGE_KEY=1 run_once
check "key change: alert sent" 'grep -q "key changed" "$T/notified"'
check "key change: no heartbeat" '[ ! -f "$T/hb" ]'

# 5. Wrong password (8002): alert, no heartbeat, one call only.
two_configs 10 200
FAKE_FAIL_LIST=8002 run_once
check "8002: alert sent" 'grep -q "Wrong Proton password" "$T/notified"'
check "8002: no heartbeat" '[ ! -f "$T/hb" ]'
check "8002: single Proton call" '[ "$(wc -l <"$T/calls")" -eq 1 ]'

# 6. CAPTCHA (9001): alert, no heartbeat.
two_configs 10 200
FAKE_FAIL_LIST=9001 run_once
check "9001: alert sent" 'grep -q "CAPTCHA" "$T/notified"'

# 7. Error 2028 without an allowlist: alert, never revokes.
two_configs 10 200
FAKE_FAIL_RENEW=2028 run_once
check "2028: no revoke without allowlist" '! grep -q revoke-serial "$T/calls"'
check "2028: alert sent" '[ -f "$T/notified" ]'
check "2028: no heartbeat" '[ ! -f "$T/hb" ]'

# 8. Error 2028 with an allowlisted serial: revokes only that one, then renews.
two_configs 10 200
FAKE_FAIL_RENEW=2028 REVOKE_ALLOWED_SERIALS=ZZ run_once
check "2028 allowlisted: revokes ZZ" 'grep -q -- "--revoke-serial ZZ" "$T/calls"'
check "2028 allowlisted: never revokes anything else" '[ "$(grep -c revoke-serial "$T/calls")" -eq 1 ]'
check "2028 allowlisted: renewal then succeeds" '[ -f "$T/hb" ]'

echo
if [ "$FAILS" -eq 0 ]; then echo "all passed"; else echo "$FAILS failed"; exit 1; fi
