# Changelog

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
