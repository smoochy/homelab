# Kuma watchdog

Uptime Kuma is the thing that tells you when something is down. Two configuration faults make it go quiet without any alert at all, and neither of them can be reported by Kuma itself:

- A monitor with no notification attached goes down and nobody hears about it.
- A maintenance window that never lifts suppresses every alert for the monitors inside it, indefinitely.

This script checks for both every 30 minutes and posts findings straight to a Discord webhook, deliberately bypassing Kuma.

## How it reads state

Over the Socket.IO admin API, inside the container, via `docker exec <container> node -`. Not from `kuma.db`.

Two reasons. Kuma derives a window's status from its dates at call time, so the `active` column stays `1` on a `single` window that expired months ago and is worthless as a signal. And a host-side `sqlite3` read of the `maintenance` table does not reliably see the container's writes: a window created over the socket and immediately confirmed by `getMaintenanceList` did not appear in a host-side `select` at all, while the same host-side read of the `monitor` table was correct. The socket is the source of truth for maintenance state.

`getMaintenanceList` supplies `status` and `dateRange`; `getMonitorList` supplies `notificationIDList` per monitor.

## Findings

- `maintenance-no-end:<id>` - the window is `under-maintenance` and has no end date, so nothing will ever lift it. Reported at once, no waiting period, because this is exactly the failure that stranded monitors for months.
- `maintenance-too-long:<id>` - the window is `under-maintenance` and started more than `MAINTENANCE_MAX_HOURS` ago (default 6).
- `monitor-no-notification:<id>` - an active monitor with no notification attached. Set `INCLUDE_PAUSED_MONITORS=1` to include paused ones.

Each finding is posted once and then repeated every `RESEND_HOURS` (default 24) while the condition holds. A finding that disappears falls out of `kuma_watchdog.state`, so its next occurrence is reported as new again. The state file is only written after a successful Discord post, so a failed post is retried on the next run instead of being silently marked as delivered.

## Setup

1. `cp .env.example .env` and fill in the Kuma credentials and the Discord webhook.
2. Deploy the directory to `/mnt/user/appdata/uptimekuma/scripts/kuma_watchdog/`, strip CRLF, and `chmod +x kuma_watchdog.sh`.
3. Add an Unraid User Scripts entry that calls the deployed copy, scheduled every 30 minutes, mirroring the `SABnzbd Speed Monitor` entry.

## Check

`check_watchdog.sh` covers the resend logic, which is the only non-trivial part: it feeds a fixed findings payload past the collector and asserts that a fresh finding posts, an already-posted one stays silent, and one older than the resend interval posts again.
