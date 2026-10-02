# Changelog

## 2026-08-28

### Self-expiring maintenance windows instead of a manual window with a latch

- Every run now creates its own `single`-strategy maintenance window with a real start and end date, owns it, and deletes it when it stops. The `manual` strategy, the reuse-by-title lookup and the `KUMA_DEFAULT_MAINTENANCE_ID` override are gone: a run that dies mid-backup can no longer leave monitors suppressed forever, because Kuma derives the window status from its dates every time it is asked.
- Removed the `STATE_STARTED_BY_SCRIPT` latch on both the start and the stop side. The state file now carries the maintenance id and the window end epoch, and the stop path always ends by detaching every monitor and deleting the window.
- Stopped reading the `active` column from `kuma.db` to decide whether a window is suppressing alerts. That column stays `1` for an expired `single` window forever, so it never answered that question.
- Only monitors whose readiness the post-run phase can actually verify enter the window: docker monitors mapped to a container, http monitors with a resolvable url, and dns monitors. Push monitors and other unmapped types stay armed and are logged.
- Replaced `KUMA_POST_RUN_TIMEOUT_SECONDS` with `KUMA_MAINTENANCE_WINDOW_MINUTES` (default 30). The post-run poll is bounded by the window's own end instead of a separate timeout, and reaching that bound now removes the window and re-arms the unconfirmed monitors rather than deliberately leaving them suppressed.
- Dropped the last host side `kuma.db` references, `KUMA_DB_FILE`, `KUMA_DB_PATH` and the `sqlite3` requirement. The database lives on the Unraid user share in WAL mode, and a host side read between two socket sessions makes the maintenance row Kuma just committed disappear, which then fails the attach with `FOREIGN KEY constraint failed`. Everything comes over the socket.
- Documented the two conventions this design depends on: the `uptime-kuma` container must keep its `TZ`, because the window dates are host local time and removing it shifts every window, and a window started by hand in the Kuma UI always gets an end date, four hours by default.

## 2026-04-12

### Direct cache path defaults for Unraid

- Switched the tracked `uptime-kuma` stack volume from
  `/mnt/user/appdata/uptimekuma` to `/mnt/cache/appdata/uptimekuma` so the
  SQLite runtime avoids the `shfs` user-share path on Unraid.
- Updated the helper to prefer `/mnt/cache/appdata` automatically when that
  direct cache path exists on the host.
- Updated `.env.example` and the published README guidance to point host-side
  `APPDATA_ROOT` and `KUMA_DB_FILE` at the direct cache path for SQLite-backed
  deployments on Unraid.

## 2026-03-28

### DNS monitor readiness support

- Added post-run readiness handling for unmapped Uptime Kuma `dns` monitors so
  DNS resolver checks can leave maintenance without a container mapping.
- Added `KUMA_POST_RUN_DNS_TIMEOUT_SECONDS` to `.env.example` for per-probe DNS
  readiness control.
- Updated the published README to document DNS-aware post-run behavior and the
  sanitized configuration surface.
- Verified the helper changes with `bash -n`, direct DNS probe validation, and
  an end-to-end start/stop maintenance test against the target Uptime Kuma
  maintenance workflow.

## 2026-03-15

### Initial release

- First repository release of `appdata_backup_kuma_maintenance` as an Unraid
  host-side helper for coordinating Uptime Kuma maintenance around
  `appdata.backup` hook execution.
- Added:
  - `appdata_backup_kuma_helper.sh`
  - `appdata_backup_kuma_pre_run.sh`
  - `appdata_backup_kuma_post_run.sh`
  - `.env.example`
  - `README.md`
  - `CHANGELOG.md`
- Added documentation for host-side installation, hook wiring, configuration,
  runtime artifacts, and readiness-based maintenance release behavior.
