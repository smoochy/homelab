# Changelog

## 2026-08-28

- Added `kuma_watchdog.sh`: reports monitors with no notification attached and maintenance windows that have been suppressing alerts for more than 6 hours, straight to a Discord webhook rather than through Kuma, repeating every 24 hours while the condition holds.
- Reads state over the Kuma Socket.IO API instead of `kuma.db`. A host-side `sqlite3` read of the `maintenance` table does not reliably see the container's writes, and the `active` column stays `1` on an expired `single` window, so neither is usable as a signal.
- A window that is under maintenance with no end date is reported immediately, without waiting for the 6 hour threshold, because nothing will ever lift it.
- Added `check_watchdog.sh` covering the resend logic, plus `.env.example` and `README.md`.
