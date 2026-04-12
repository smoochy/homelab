# Unraid Appdata Backup Uptime Kuma Maintenance Helper

This host-side helper coordinates Uptime Kuma maintenance around `appdata.backup`
pre-run and post-run hooks on Unraid. It starts a dedicated manual maintenance
before containers are stopped and releases monitors again after the related
services, mapped HTTP endpoints, and supported unmapped DNS monitors are ready.

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
- Reuses an existing manual maintenance or creates one when needed
- Starts maintenance for the selected Uptime Kuma monitor set before backup
- Preserves an already-active maintenance instead of forcing ownership changes
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
- `sqlite3`
- `stat`

Uptime Kuma must be reachable through the local Docker runtime, and the host
must be able to access the `kuma.db` database file. The helper also expects the
standard Uptime Kuma container runtime so the embedded `node`-based socket
action can run through `docker exec`.

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
- `KUMA_DB_FILE`: host path to `kuma.db`
- `KUMA_CONTAINER_NAME`: Docker container name for Uptime Kuma
- `KUMA_BASE_URL`: Uptime Kuma URL as seen from inside the container
- `KUMA_DEFAULT_MAINTENANCE_ID`: optional fixed manual maintenance to reuse
- `KUMA_DEFAULT_MAINTENANCE_TITLE`: maintenance title used when creating or
  reusing a manual maintenance by name
- `KUMA_INCLUDE_INACTIVE_MONITORS`: controls whether inactive monitors are
  included in the maintenance set
- `KUMA_POST_RUN_TIMEOUT_SECONDS`: total wait time before the helper leaves
  remaining monitors in maintenance
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

On Unraid, point `APPDATA_ROOT` and `KUMA_DB_FILE` at the direct cache path
such as `/mnt/cache/appdata` instead of `/mnt/user/appdata` when the target app
stores SQLite data. That avoids routing live database access through the `shfs`
user-share path.

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

`start` resolves or creates a dedicated manual maintenance, fetches the monitor
list from Uptime Kuma, and enables maintenance for the selected monitor set.
If the target maintenance was already active before the backup started, the
helper records that state and leaves ownership with the pre-existing
maintenance.

`stop` reads the helper state, rebuilds the monitor-to-container mapping, and
waits until mapped Docker services, relevant HTTP monitors, and supported
unmapped DNS monitors are ready again. As services recover, it removes only the
corresponding monitors from maintenance. If the configured timeout is reached,
it leaves the remaining monitors in maintenance and logs the unresolved state
for follow-up.

## Logging

Runtime output is written to `appdata_backup_kuma.log` in the helper directory.
When `VERBOSE_OUTPUT=1`, normal progress is also printed to stdout. When
`VERBOSE_OUTPUT=2`, the helper additionally prints mapping and readiness detail
that is useful for maintenance validation.

## Notes

- This helper expects a dedicated manual maintenance, not a recurring strategy.
- If `KUMA_DEFAULT_MAINTENANCE_ID` is not set, the helper tries to reuse a
  manual maintenance with the configured title before creating a new one.
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
