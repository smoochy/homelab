# Changelog

## 2026-03-15

### Queue-aware baseline reset

- Baseline tracking now includes the active SABnzbd queue identity via
  `slots[0].nzo_id`.
- The monitor now resets its measurement baseline immediately when the queue
  grows during warmup or when the active queue identity changes.
- This prevents stale or misleading average throughput values when new
  downloads enter the queue or the queue context changes during the sample
  window.

## 2026-03-14

### Initial release

- First repository release of `monitor_sab_speed` as a host-side throughput
  monitoring and recovery automation helper.
- Added:
  - `monitor_sab_speed.sh`
  - `README.md`
  - `CHANGELOG.md`
  - `.env.example`
- Added host-side monitoring, maintenance automation, and recovery support for:
  - shared Komodo stacks
  - split Komodo stacks
  - Komodo procedures
  - direct Docker container recovery
  - optional Uptime Kuma maintenance handling
- Added documentation for shared `.env` configuration, host scheduling,
  testing, and operational logging with Unraid User Scripts and plain cron.
