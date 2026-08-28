#!/bin/bash
# Supervisor for the two halves of the WhatPulse container (issue #1582).
#
# Upstream runs the capture service under systemd and the client under a desktop
# session. There is neither here, so this script builds the smallest desktop the
# client will accept, starts both halves and ends the container as soon as any of
# them stops - the restart policy is the supervisor of last resort, and a
# half-running container that still looks up is the failure mode worth avoiding.
#
# It starts as root because the capture service refuses to run as anyone else
# (see below). Everything else is dropped to the unprivileged whatpulse user.
set -uo pipefail

APP_USER=whatpulse
APP_HOME=/home/whatpulse
DATA_DIR="$APP_HOME/.local/share"

log() { printf '%s [entrypoint] %s\n' "$(date -Is)" "$*"; }
asuser() { runuser -u "$APP_USER" -- "$@"; }

# The VNC front end is reachable from the LAN, because the container shares the
# host's network namespace and there is no desktop on the server to reach it
# from. An unauthenticated VNC session is remote control of the whole client, so
# a password is required; the override exists for a throwaway local build and
# says what it is doing.
if [ -z "${WP_VNC_PASSWORD:-}" ]; then
    if [ "${WP_VNC_ALLOW_INSECURE:-no}" != "yes" ]; then
        log "refusing to start: WP_VNC_PASSWORD is unset and WP_VNC_ALLOW_INSECURE is not yes"
        exit 1
    fi
    log "WARNING: VNC is running without a password because WP_VNC_ALLOW_INSECURE=yes"
    VNC_AUTH=(-nopw)
else
    asuser install -m 0700 -d "$APP_HOME/.vnc"
    asuser x11vnc -storepasswd "$WP_VNC_PASSWORD" "$APP_HOME/.vnc/passwd" >/dev/null 2>&1
    VNC_AUTH=(-rfbauth "$APP_HOME/.vnc/passwd")
fi

# The persistent volume arrives owned by whoever created it on the host, and the
# client writes its settings, its statistics database and its logs in there. A
# client that cannot write its own data directory starts and then exits without
# saying why, so the ownership is fixed here rather than left to the host.
mkdir -p "$DATA_DIR"
chown -R "$APP_USER:$APP_USER" "$APP_HOME"

pids=()
track() { pids+=("$1"); }
# shellcheck disable=SC2329  # invoked by the trap below
shutdown() {
    log "shutting down"
    kill "${pids[@]}" 2>/dev/null
    wait 2>/dev/null
}
trap shutdown EXIT INT TERM

# A stopped container keeps its writable layer, so the lock file and socket of
# the previous X server are still there after `docker start` and Xvfb refuses
# the display with "Server is already active" - forever, since the retry hits
# the same leftovers. Nothing else owns them at this point: the container was
# just started and this process is pid 1.
rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}"

log "starting Xvfb on $DISPLAY (${WP_SCREEN})"
asuser Xvfb "$DISPLAY" -screen 0 "$WP_SCREEN" -nolisten tcp &
track $!

# The display has to be up before anything tries to open a window on it, and
# Xvfb reports readiness only by answering, so it is polled rather than slept on.
for _ in $(seq 1 30); do
    asuser xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
    sleep 1
done
if ! asuser xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "Xvfb did not come up on $DISPLAY"
    exit 1
fi

# The client starts minimised into the system tray and has no other window. On a
# bare X server there is no tray, so it exits immediately after initialising,
# with status 0 and nothing in its log - which is why a window manager and a tray
# are part of the image rather than decoration. openbox draws the window frames
# the settings dialogs need; trayer is the tray the client docks into.
log "starting the window manager and the tray"
asuser openbox &
track $!
sleep 1
asuser trayer --edge bottom --align right --width 10 --height 24 &
track $!
sleep 1

# x11vnc listens on loopback only: websockify is its single client, and the port
# that is meant to be reachable is the web one below. In the host network
# namespace this is the difference between one exposed port and two.
log "starting x11vnc on 127.0.0.1:${WP_VNC_PORT}"
asuser x11vnc -display "$DISPLAY" -localhost -rfbport "$WP_VNC_PORT" \
    -forever -shared -noxdamage -quiet "${VNC_AUTH[@]}" &
track $!

log "starting noVNC on :${WP_WEB_PORT}"
asuser websockify --web /usr/share/novnc "$WP_WEB_PORT" "127.0.0.1:${WP_VNC_PORT}" &
track $!

# The client talks to a session bus and there is none in a container, so it gets
# one of its own. Without it the client still runs, but every desktop
# notification it makes is an error in the log.
log "starting the WhatPulse client"
asuser dbus-run-session -- /opt/whatpulse/AppRun &
track $!

# The capture service connects out to the client and exits when that fails, and
# the client is not listening until it has finished starting - and not at all
# until an account is linked. So it is retried rather than started once, which is
# also what makes the one-time login through the web VNC work without a restart.
#
# It runs as root: it checks for uid 0 itself and refuses otherwise, so the
# capabilities the capture actually needs cannot be handed to it on the file. The
# container still has to be granted CAP_NET_RAW and CAP_NET_ADMIN.
#
# The interface is always passed explicitly. Left to its own discovery the
# service would also take eth0, which carries the same frames as br0, and every
# byte would be counted twice (issue #1581).
#
# The heartbeat marker this container's healthcheck reads is written here rather
# than beside the client (issues #1688, #1704), because this loop is the only
# place that knows whether the capture is actually running. The service connects
# out to the client and exits when that fails, so a container whose client is
# gone, unlinked or wedged sits in the 15s backoff below - up while capturing
# nothing. Marking only while the service is alive makes exactly that state go
# stale, which is what the /dev/tcp port connect it replaces was watching, minus
# the port connect the convention rules out.
#
# The marker lives in /run, in the writable layer: a healthcheck runs inside the
# container, and host state would survive a restart and report a dead capture as
# healthy. The toucher is killed with each attempt rather than left behind, so a
# container that has retried for a week carries one of them, not four thousand.
(
    while true; do
        log "starting the capture service on ${WP_INTERFACE}"
        whatpulse-pcap-service -i "$WP_INTERFACE" -l "" -h 127.0.0.1 -p 3499 &
        service_pid=$!
        (
            while kill -0 "$service_pid" 2>/dev/null; do
                touch /run/whatpulse.heartbeat 2>/dev/null || :
                sleep 30
            done
        ) &
        heartbeat_pid=$!
        wait "$service_pid"
        kill "$heartbeat_pid" 2>/dev/null
        wait "$heartbeat_pid" 2>/dev/null
        log "capture service exited, retrying in 15s"
        sleep 15
    done
) &
track $!

# Any of them stopping ends the container.
wait -n
log "a supervised process exited"
exit 1
