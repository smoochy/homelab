# Unraid Appdata Backup Uptime Kuma Maintenance Helper

This host-side helper coordinates Uptime Kuma maintenance around `appdata.backup`
pre-run and post-run hooks on Unraid. Each run creates its own self-expiring maintenance window before containers are stopped and releases monitors again after the related services, mapped HTTP endpoints, and supported unmapped DNS monitors are ready.

It is intended for self-hosted maintenance workflows where backup execution,
container restarts, and service readiness should be reflected in monitoring
state without repeated manual intervention.

## Table of Contents

- [Background](#background)
- [Features](#features)
- [Requirements](#requirements)
- [Files](#files)
- [Configuration](#configuration)
- [Install](#install)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Logging](#logging)
- [Notes](#notes)
- [Transparency](#transparency)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

When `appdata.backup` stops containers, a monitoring system can show widespread
failures even though the outage is planned maintenance. This helper wraps that
workflow with a dedicated Uptime Kuma maintenance so the monitoring state stays
aligned with the operational maintenance window.

The pre-run hook enables maintenance before the backup begins. The post-run
hook then waits for Docker containers, related HTTP monitors, and supported
unmapped DNS monitors to recover before monitors are released from maintenance
again.

## Features

- Runs on the Unraid host, not inside the backup job container context
- Uses dedicated `appdata.backup` pre-run and post-run hook scripts
- Creates, owns and deletes one self-expiring maintenance window per run
- Starts maintenance for the selected Uptime Kuma monitor set before backup
- Stops AutoKuma for the same window so it cannot delete label-owned monitors while their containers are down
- Waits for Docker-backed services and mapped HTTP monitors before releasing
  maintenance during post-run handling
- Probes unmapped DNS monitors directly during post-run handling so resolver
  checks can leave maintenance without a container mapping
- Leaves remaining monitors in maintenance when the post-run readiness timeout
  is reached, rather than clearing maintenance prematurely
- Supports optional host alias mapping for HTTP monitor readiness checks
- Stores helper state between pre-run and post-run execution
- Writes operational logs and can rotate the logfile after a configured number
  of days

## Requirements

The Unraid host must have:

- `bash`
- `curl`
- `docker`
- `jq`
- `stat`

Uptime Kuma must be reachable through the local Docker runtime. The helper also expects the standard Uptime Kuma container runtime so the embedded `node`-based socket action can run through `docker exec`.

This helper is designed for `appdata.backup` hook integration on Unraid. The
pre-run and post-run scripts assume the hook argument shape used by that
workflow.

## Files

- `appdata_backup_kuma_helper.sh`: main helper that starts or stops maintenance
- `appdata_backup_kuma_pre_run.sh`: pre-run hook wrapper that calls the helper
  with `start`
- `appdata_backup_kuma_post_run.sh`: post-run hook wrapper that calls the
  helper with `stop`
- `.env.example`: repository-safe configuration template
- `.env`: local host configuration file created from `.env.example`
- `appdata_backup_kuma.state`: created automatically on the host to track the
  helper-owned maintenance between runs
- `appdata_backup_kuma.log`: created automatically on the host for runtime
  logging

Only the shell scripts, `.env.example`, `README.md`, and `CHANGELOG.md` are
committed. The real `.env`, log, and state files are runtime artifacts and
should stay local to the host.

## Configuration

Copy `.env.example` to `.env` on the host and adjust the values for your
environment. The most important keys are:

- `APPDATA_ROOT`: base appdata path on the host
- `KUMA_CONTAINER_NAME`: Docker container name for Uptime Kuma
- `KUMA_BASE_URL`: Uptime Kuma URL as seen from inside the container
- `KUMA_DEFAULT_MAINTENANCE_TITLE`: title of the window each run creates
- `KUMA_MAINTENANCE_WINDOW_MINUTES`: length of that window, default 30
- `AUTOKUMA_CONTAINER_NAME`: AutoKuma container stopped for the backup window, default `autokuma`
- `KUMA_INCLUDE_INACTIVE_MONITORS`: controls whether inactive monitors are
  included in the maintenance set
- `KUMA_POST_RUN_POLL_INTERVAL_SECONDS`: readiness poll interval during post-run
- `KUMA_POST_RUN_HTTP_TIMEOUT_SECONDS`: per-request timeout for HTTP readiness
  checks
- `KUMA_POST_RUN_DNS_TIMEOUT_SECONDS`: per-probe timeout for unmapped DNS
  monitor readiness checks
- `KUMA_POST_RUN_CURL_INSECURE`: set to `1` only if HTTP readiness checks must
  ignore TLS verification temporarily
- `KUMA_HTTP_MONITOR_ALIAS_MAP`: optional JSON alias map for monitor hostnames
- `LOG_RESET_DAYS`: logfile retention before reset
- `VERBOSE_OUTPUT`: logging verbosity
- `KUMA_SOCKET_TIMEOUT_MS`, `KUMA_SOCKET_RETRIES`,
  `KUMA_SOCKET_RETRY_SLEEP_SECONDS`: retry controls for Kuma socket actions
- `KUMA_AUTH_TOKEN` or `KUMA_USERNAME` plus `KUMA_PASSWORD`: Uptime Kuma
  authentication

Nothing in this script reads `kuma.db` from the host, and nothing should. The database sits on the Unraid user share in WAL mode, and a host side reader between two socket sessions makes the maintenance row Kuma just committed disappear: the next `addMonitorMaintenance` then fails with `FOREIGN KEY constraint failed` against a window that was created seconds earlier. Reproduced deterministically with create, one `sqlite3` select on the host, attach. Everything comes over the socket instead, which is also the only source that reflects the running server's state.

Normal setup changes should only require edits in `.env`.

## Install

### 1. Copy the helper folder to the host

Place the files in a persistent host path, for example:

```text
/mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/
```

### 2. Convert to LF line endings

If the files were created or edited on Windows, convert them to LF line
endings:

```sh
sed -i 's/\r$//' /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_helper.sh
sed -i 's/\r$//' /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_pre_run.sh
sed -i 's/\r$//' /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_post_run.sh
```

### 3. Make the scripts executable

```sh
chmod +x /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_helper.sh
chmod +x /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_pre_run.sh
chmod +x /mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_post_run.sh
```

### 4. Create the local `.env` file

Use `.env.example` from this repository as the template and create the real
configuration file on the host at:

```text
/mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/.env
```

### 5. Configure the hook scripts in `appdata.backup`

Set the Unraid `appdata.backup` workflow to call:

- `appdata_backup_kuma_pre_run.sh` before containers are stopped
- `appdata_backup_kuma_post_run.sh` after the backup run finishes

The wrapper scripts accept the hook arguments provided by `appdata.backup` and
forward control to the main helper.

## Usage

For direct host-side testing, you can run:

```sh
/mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_helper.sh start
/mnt/user/appdata/uptimekuma/scripts/appdata_backup_maintenance/appdata_backup_kuma_helper.sh stop
```

In normal operation, `appdata.backup` should invoke the pre-run and post-run
wrappers automatically.

## How It Works

`start` creates its own maintenance window with the `single` strategy and a real start and end date, `KUMA_MAINTENANCE_WINDOW_MINUTES` long (default 30), then attaches the eligible monitors to it. Every run owns exactly one window: nothing is reused by title, so two overlapping runs never fight over the same row, and a window left behind by a crashed run expires on its own dates rather than suppressing alerts forever.

Only monitors whose readiness the `stop` side can actually confirm enter the window: mapped Docker monitors, HTTP monitors resolvable through `KUMA_HTTP_MONITOR_ALIAS_MAP`, and DNS monitors. A push monitor has nothing to probe, so it stays armed instead of being released blind.

`stop` reads the helper state, rebuilds the monitor-to-container mapping, and waits until those monitors are ready again, releasing each one as its service recovers. The poll never outlives the window itself, because once the window's end date has passed Kuma has stopped suppressing anyway. However the poll ends, the run detaches every monitor and deletes the window it created, so a run can never leave its own window standing.

`start` and `stop` also stop and start AutoKuma around the backup. AutoKuma reconciles monitors from container labels, so while the backup has the containers stopped it would see the labels disappear and delete the very monitors this maintenance is protecting. The restart in `post_run` is deliberately not guarded by the helper's exit status: a failed stop must never leave AutoKuma down.

## Logging

Runtime output is written to `appdata_backup_kuma.log` in the helper directory.
When `VERBOSE_OUTPUT=1`, normal progress is also printed to stdout. When
`VERBOSE_OUTPUT=2`, the helper additionally prints mapping and readiness detail
that is useful for maintenance validation.

## Notes

- The helper creates and deletes its own `single` window per run. There is no window to configure and no id to pin; `KUMA_DEFAULT_MAINTENANCE_ID` is gone.
- The window is created with `timezoneOption: "SAME_AS_SERVER"` and its dates are host local time. The `uptime-kuma` container must keep its `TZ` set to the host's timezone: removing it shifts every window by the offset, so a window would start and end at the wrong wall-clock time.
- A window started by hand in the Kuma UI always gets an end date, four hours unless there is a reason for another value. A window with no end date suppresses alerts until somebody remembers it, which is the failure this whole design exists to prevent. The Kuma watchdog reports one within 30 minutes.
- Host-only runtime artifacts such as `.env`, `.log`, and `.state` should not
  be committed to the repository.
- The published `.env.example` is intentionally sanitized. Keep live hostnames,
  alias mappings, usernames, passwords, and tokens in the local host `.env`
  only.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for script-specific change history.

## Transparency

The code, documentation, and related project materials in this repository were
created and refined with AI assistance. All generated output was reviewed and
adapted before publication.

## Maintainers

- [smoochy](https://github.com/smoochy)

## Contributing

Issues and pull requests are welcome. Keep changes focused on reliable backup
maintenance behavior, update the host setup instructions when runtime
requirements change, and keep the published configuration examples free of live
secrets or host-specific runtime artifacts.

## License

[MIT](../../../../LICENSE) 2026 [smoochy](https://github.com/smoochy)
