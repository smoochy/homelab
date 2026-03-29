# SABnzbd Throughput Monitor and Recovery Automation

This host-side automation script watches active SABnzbd queue activity,
calculates the average transfer speed over a rolling time window, and triggers
a configured recovery action when sustained throughput drops below a defined
threshold.

It is intended for self-hosted Docker and Unraid environments where SABnzbd is
part of a larger automation stack and occasional network or VPN degradation is
better handled through controlled host-side maintenance than repeated manual
intervention.

## Table of Contents

- [Background](#background)
- [Features](#features)
- [Requirements](#requirements)
- [Files](#files)
- [Configuration](#configuration)
- [Install](#install)
- [Usage](#usage)
- [Testing](#testing)
- [How It Works](#how-it-works)
- [Logging](#logging)
- [Notes](#notes)
- [Transparency](#transparency)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

Some SABnzbd setups occasionally slow down because the surrounding network path,
VPN session, or stack state degrades over time. In those cases, a targeted
recovery action can restore normal throughput, but manually watching for that
condition is not a reliable long-term operational workflow.

This script moves that check to the Docker or Unraid host. It polls the local
SABnzbd API, measures average progress over the configured time window, and only
triggers recovery when there is an active download and the observed average
speed remains below the configured threshold.

## Features

- Runs on the Docker or Unraid host, not inside the SABnzbd container
- Calculates average speed over a configurable time window
- Measures that average only while the queue context stays stable
- Skips idle, paused, and otherwise non-active queue states
- Prevents repeated recovery loops with a configurable cooldown period
- Supports multiple recovery paths:
  - `komodo_stack`
  - `komodo_split_stacks`
  - `komodo_procedure`
  - `docker`
- Prints operational status output for schedulers such as Unraid User Scripts
- Stores state between runs so a frequent cron schedule can still use a longer
  measurement window
- Can clear its own logfile after a configurable number of days
- Uses a lock directory so only one run executes at a time
- Supports env-based low-speed simulation for safe recovery-path testing
- Can call an optional Uptime Kuma helper script around recovery

## Requirements

- SABnzbd must be reachable from the host through its local API endpoint
- The host must have:
  - `bash`
  - `awk`
  - `curl`
  - `jq`
  - `stat`
- For `docker` recovery mode, the host must also have `docker`
- For `komodo_*` recovery modes, the host must be able to run:
  - `docker exec <komodo-core-container> km execute ...`
- For `komodo_*` recovery modes, set `KOMODO_CLI_KEY` and `KOMODO_CLI_SECRET` in `.env`
- SABnzbd's `sabnzbd.ini` must be readable from the host so the script can read
  the API key from the `[misc]` section

## Files

- `monitor_sab_speed.sh`: host-side monitoring and recovery script
- `monitor_sab_speed_kuma.sh`: optional helper for dedicated Uptime Kuma maintenance control
- `.env.example`: shared example configuration for both scripts
- `monitor_sab_speed.state`: created automatically and stores the previous
  sample timestamp and queue size
- `monitor_sab_speed.log`: created automatically and stores runtime output
- `monitor_sab_speed.lock/`: created automatically while a run is active

Only `monitor_sab_speed.sh`, `monitor_sab_speed_kuma.sh`, and `.env.example` are committed. The real `.env` plus the state, log, and lock artifacts are
runtime files and should stay untracked.

## Configuration

Copy `.env.example` to `.env` on the host and adjust that one file.
The most important keys are:

- `APPDATA_ROOT`: example appdata root path on the host
- `SAB_APPDATA_DIR`: host path to the SABnzbd appdata directory containing
  `sabnzbd.ini`
- `SAB_HOST`: host or IP address used to reach the SABnzbd API
- `SAB_PORT`: published SABnzbd port on the host
- `SAB_URL_BASE`: SABnzbd URL base path, for example `/sabnzbd` or an empty
  string
- `AVERAGE_WINDOW_MINUTES`: how many minutes of progress should be used for the
  average speed calculation
- `SPEED_THRESHOLD_MBPS`: minimum acceptable average throughput in MB/s before
  recovery is triggered
- `COOLDOWN_MINUTES`: minimum time between two recovery actions
- `LOG_RESET_DAYS`: number of days after which the logfile is cleared
- `RECOVERY_METHOD`: which recovery path to use
- `KOMODO_STACK_NAME`: shared stack name for `komodo_stack`
- `GLUETUN_STACK_NAME`: gluetun stack name for `komodo_split_stacks`
- `SAB_STACK_NAME`: SABnzbd stack name for `komodo_split_stacks`
- `KOMODO_PROCEDURE_NAME`: procedure name for `komodo_procedure`
- `KOMODO_CLI_KEY`, `KOMODO_CLI_SECRET`: Komodo CLI credentials used for authenticated `km execute` calls
- `ENABLE_RECOVERY`: set to `0` for dry-run mode without actual recovery actions
- `ENABLE_KUMA_MAINTENANCE`: set to `1` to call `monitor_sab_speed_kuma.sh` around recovery
- `VERBOSE_OUTPUT`: `1` writes to the logfile and prints status lines to stdout, `0` writes only to the logfile
- `KUMA_DEFAULT_MAINTENANCE_ID`: optional fixed manual maintenance ID in Uptime Kuma
- `KUMA_DEFAULT_MONITOR_IDS`: monitors the helper should attach to the dedicated maintenance
- `KUMA_SOCKET_TIMEOUT_MS`, `KUMA_SOCKET_RETRIES`, `KUMA_SOCKET_RETRY_SLEEP_SECONDS`: reliability tuning for Kuma socket login and action retries
- `KUMA_AUTH_TOKEN` or `KUMA_USERNAME` plus `KUMA_PASSWORD`: Kuma authentication

Normal setup changes should only require edits in `.env`. The scripts keep internal path handling and compatibility aliases in code, but those are not intended as the main configuration surface.

### Recovery mode examples

Shared Komodo stack for `gluetun + sabnzbd`:

```bash
RECOVERY_METHOD="komodo_stack"
KOMODO_STACK_NAME="sabnzbd"
```

Separate Komodo stacks for `gluetun` and `sabnzbd`:

```bash
RECOVERY_METHOD="komodo_split_stacks"
GLUETUN_STACK_NAME="gluetun"
SAB_STACK_NAME="sabnzbd"
WAIT_AFTER_GLUETUN_SECONDS="20"
```

Komodo authentication for `komodo_*` recovery modes:

```bash
KOMODO_CLI_KEY="your-komodo-cli-key"
KOMODO_CLI_SECRET="your-komodo-cli-secret"
```

How to get the Komodo CLI key and secret:

- open the Komodo web UI
- open your user profile
- go to `Api Keys`
- create a new API key
- copy both the generated `key` and `secret`
- put them into `KOMODO_CLI_KEY` and `KOMODO_CLI_SECRET` in `.env`

Notes:

- the `secret` is typically only shown once when the key is created, so save it immediately
- if you prefer not to use your personal user, create a dedicated service user in Komodo and generate an API key for that user instead
- the chosen user must have permission to execute the target stack or procedure

Safe dry-run mode for testing:

```bash
ENABLE_RECOVERY="0"
```

Environment-only test flags:

- `FORCE_LOW_SPEED_TEST=1`: injects a low-speed average into the normal threshold, cooldown, and recovery path
- `FORCE_LOW_SPEED_MBPS=0.50`: optional forced average in MB/s used for the simulated run
- `IGNORE_COOLDOWN_FOR_TEST=1`: optional override that bypasses cooldown when the low-speed test flag is active

Uptime Kuma options:

- enable the helper with `ENABLE_KUMA_MAINTENANCE=1`
- keep Kuma IDs, retry settings, and credentials in the shared `.env`
- use `.env.example` from the repository as the template for the full setup

## Install

### 1. Copy the script to the host

Place the script in a persistent host path, for example:

```text
/mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

This script is intended to run on the host. Do not assign it as a SABnzbd
post-processing script.

### 2. Convert to LF line endings

If the file was created or edited on Windows, convert it to LF line endings:

```sh
sed -i 's/\r$//' /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
sed -i 's/\r$//' /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed_kuma.sh
```

### 3. Make the script executable

```sh
chmod +x /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
chmod +x /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed_kuma.sh
```

### 4. Create the local `.env` file

Use `.env.example` from this repository as the template and create the real configuration file on the host at `/mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/.env`.

### 5. Adjust the `.env` file

Edit `/mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/.env` so the host paths, API endpoint,
recovery method, Kuma integration, and credentials match your setup.

If you use a `komodo_*` recovery mode, also fill in `KOMODO_CLI_KEY` and `KOMODO_CLI_SECRET`.

### 6. Verify host-side API access

The script uses the local SABnzbd API and reads the API key from `sabnzbd.ini`.
Before scheduling it, confirm that:

- the host can reach the published SABnzbd API URL
- the configured `SAB_APPDATA_DIR` points to the correct `sabnzbd.ini`
- `jq`, `curl`, and `awk` are available on the host

### 7. Schedule the script on the host

Run the script every minute. The script keeps its own previous sample in
`monitor_sab_speed.state`, so a one-minute schedule is still the right choice
when `AVERAGE_WINDOW_MINUTES="2"`.

#### Option A: Unraid User Scripts

Create a new User Scripts entry and use:

```bash
#!/bin/bash
/mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

Recommended schedule:

```cron
* * * * *
```

For a safe test run without triggering recovery actions:

```bash
#!/bin/bash
FORCE_LOW_SPEED_TEST=1 RESTART_ENABLED=0 /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

#### Option B: Plain cron

Example cron entry:

```cron
* * * * * /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

If you prefer a dedicated wrapper script, keep the schedule at every minute and
call the monitor from that wrapper.

## Usage

Once scheduled, the script runs on the host and prints a compact operational
summary for each run.

Typical flow:

1. It reads the SABnzbd API key from `sabnzbd.ini`.
2. It requests the current queue state through the local API.
3. It stores a baseline sample when needed.
4. On later runs, it calculates the average throughput over the configured
   window.
5. It decides whether recovery should be skipped, deferred, or triggered.

That throughput window is tied to a stable queue context. If the queue grows
materially or the active SABnzbd job changes before the window completes, the
script resets the baseline and starts a fresh measurement window instead of
using stale data.

## Uptime Kuma Maintenance

When `ENABLE_KUMA_MAINTENANCE="1"`, `monitor_sab_speed.sh` calls
`monitor_sab_speed_kuma.sh` to toggle a dedicated manual Uptime Kuma
maintenance around the recovery action.

Recommended setup:

- use a dedicated manual maintenance for this script, not a recurring/shared one
- set `KUMA_DEFAULT_MAINTENANCE_ID` in `.env` if you already created that maintenance in Kuma
- otherwise leave the ID empty and set `KUMA_DEFAULT_MONITOR_IDS` there so the helper can auto-create and map a manual maintenance on first use
- put `KUMA_AUTH_TOKEN` or `KUMA_USERNAME` and `KUMA_PASSWORD` into the same `.env`
- use `.env.example` in this repository as the starting template

Behavior:

- the script starts the manual maintenance immediately before recovery
- it stops the maintenance after the recovery attempt completes
- it also removes the monitor mapping on stop, then recreates it automatically on the next start
- it triggers an immediate refresh on configured active monitors after start and stop so the heartbeat history records the maintenance transition without waiting for the normal monitor interval
- Kuma socket actions use a configurable timeout and retry with backoff for transient login/socket timeouts
- the normal start and stop flows are bundled into a single Kuma session each, so monitor mapping, maintenance toggling, and heartbeat refresh do not require separate logins
- example: if `start_bundle` hits a temporary `login timed out`, the helper waits `KUMA_SOCKET_RETRY_SLEEP_SECONDS` and retries until `KUMA_SOCKET_RETRIES` is exhausted
- if the maintenance was already active before the run, the script leaves it active
- if recovery is disabled with `RESTART_ENABLED=0`, the script only logs that Kuma maintenance would have started
- the script refuses to use non-manual maintenances by ID, so recurring windows such as backups are not accidentally paused or resumed

Example dedicated setup for local monitor IDs `28` and `41`:

```dotenv
ENABLE_KUMA_MAINTENANCE="1"
KUMA_DEFAULT_MONITOR_IDS="28,41"
KUMA_SOCKET_TIMEOUT_MS="20000"
KUMA_SOCKET_RETRIES="3"
KUMA_SOCKET_RETRY_SLEEP_SECONDS="2"

# In /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/.env
KUMA_AUTH_TOKEN=""
KUMA_USERNAME="your-kuma-user"
KUMA_PASSWORD="your-kuma-password"
```

How to find monitor IDs in Uptime Kuma:

- open the monitor in the Uptime Kuma web UI
- look at the browser address bar
- the numeric part in the URL is the monitor ID, for example `.../dashboard/28` or `.../monitor/28`
- repeat this for each monitor you want to include, then list them in `KUMA_DEFAULT_MONITOR_IDS` as a comma-separated value such as `28,41`

## Testing

The low-speed test mode is controlled entirely through environment variables, so
cron or User Scripts can trigger validation runs without editing the scripts.

What the simulation does:

- still polls the real SABnzbd queue and logs the current status when available
- skips the baseline wait and minimum sample-window requirement for that run
- injects `FORCE_LOW_SPEED_MBPS` into the normal threshold, cooldown, and recovery decision path
- keeps cooldown active by default and only bypasses it when `IGNORE_COOLDOWN_FOR_TEST=1` is set
- logs clearly that the run was forced for testing
- logs whether the Kuma helper would start or be skipped when Kuma integration is enabled
- does not change the normal queue-baseline reset rules when test mode is off

Recommended commands:

```bash
FORCE_LOW_SPEED_TEST=1 RESTART_ENABLED=0 /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

This is the safest output-only test. It exercises the low-speed branch, logs the
simulated condition, confirms that recovery is suppressed when
`RESTART_ENABLED=0`, and only reports what the Kuma helper would do.

```bash
FORCE_LOW_SPEED_TEST=1 /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

This runs the real recovery path using the forced low-speed value. Use
`FORCE_LOW_SPEED_MBPS=0.50` or another value below your threshold when you want
predictable percentage output.

```bash
FORCE_LOW_SPEED_TEST=1 IGNORE_COOLDOWN_FOR_TEST=1 /mnt/user/appdata/sabnzbd/scripts/sab_speed_monitor/monitor_sab_speed.sh
```

Use this only for repeated validation runs when the normal cooldown would block a
second test immediately after the first one.

## How It Works

The script only reacts when SABnzbd is actively downloading and there is data
left in the queue.

Recovery is skipped when:

- SABnzbd is not currently downloading
- the queue data is incomplete
- the current run only establishes the baseline sample
- the active SABnzbd queue identity changed and the script reset the baseline
- the previous sample is younger than the configured average window
- the queue grew significantly during warmup, meaning the earlier baseline is no
  longer a good comparison point
- the average speed is above the configured threshold
- the average speed is below the threshold but the cooldown is still active

Recovery is triggered when:

- SABnzbd reports an active download
- the elapsed sample window is at least the configured minimum window
- the computed average speed remains below the threshold
- the cooldown period has expired

Depending on `RECOVERY_METHOD`, the script either runs a shared Komodo stack
recovery, runs split Komodo stack recovery in sequence, executes a Komodo
procedure, or falls back to direct Docker container restarts. If Kuma
integration is enabled, `monitor_sab_speed_kuma.sh` starts a dedicated manual
maintenance before recovery and stops it again afterwards unless it was already
active before the run.

## Logging

The script always writes operational messages to `monitor_sab_speed.log`. When
`VERBOSE_OUTPUT="1"`, it also prints the same lines to stdout. When
`VERBOSE_OUTPUT="0"`, it writes only to the logfile.

Example User Scripts output:

```text
2026-03-14 20:05:23 status=Downloading, current=12.34 MB/s, remaining=1786.62 MB, threshold=10 MB/s, window=2 min
2026-03-14 20:05:23 baseline sample stored, waiting for next run
2026-03-14 20:06:23 status=Downloading, current=7.42 MB/s, remaining=1650.12 MB, threshold=10 MB/s, window=2 min
2026-03-14 20:06:23 sample age 60s is below target window 120s, waiting
2026-03-14 20:07:23 status=Downloading, current=5.86 MB/s, remaining=1510.44 MB, threshold=10 MB/s, window=2 min
2026-03-14 20:07:23 average=6.84 MB/s over 120s (68.4% of threshold 10 MB/s)
2026-03-14 20:07:23 speed is below threshold, starting recovery via komodo_stack
2026-03-14 20:07:23 recovery: komodo restart-stack sabnzbd
```

Example warmup reset output after a queue change:

```text
2026-03-15 11:28:01 status=Downloading, current=66.93 MB/s, remaining=8374.90 MB, threshold=10 MB/s, window=2 min
2026-03-15 11:28:01 baseline sample stored, waiting for next run
2026-03-15 11:29:01 status=Downloading, current=64.46 MB/s, remaining=18135.96 MB, threshold=10 MB/s, window=2 min
2026-03-15 11:29:01 queue grew by more than 1 MB during warmup, baseline reset
2026-03-15 11:30:02 status=Downloading, current=66.06 MB/s, remaining=6525.88 MB, threshold=10 MB/s, window=2 min
2026-03-15 11:30:02 sample age 61s is below target window 120s, waiting
```

When testing in dry-run mode with `FORCE_LOW_SPEED_TEST=1 RESTART_ENABLED=0` and Kuma enabled:

```text
2026-03-14 20:07:23 simulation: low-speed test enabled
2026-03-14 20:07:23 simulation: forced average=0.50 MB/s, cooldown_override=0, restart_enabled=0
2026-03-14 20:07:23 simulation: skipping baseline wait and sample window checks for this run
2026-03-14 20:07:23 simulation: average=0.50 MB/s over 0s (5.0% of threshold 10 MB/s)
2026-03-14 20:07:23 simulation: cooldown is not active for this run
2026-03-14 20:07:23 simulation: kuma helper would be started before recovery
2026-03-14 20:07:23 speed is below threshold, starting recovery via komodo_stack
2026-03-14 20:07:23 simulation: recovery would be suppressed because RESTART_ENABLED=0
2026-03-14 20:07:23 dry-run: recovery suppressed for method=komodo_stack
```

## Notes

- This is a host automation script, not a container-internal helper
- The script calculates throughput from queue progress over time, not from a
  single instantaneous speed value
- The average window is only valid while the active queue context remains
  stable; if the queue grows or the active job changes, the baseline is reset
- The state file is required for multi-run averaging and should not be deleted
  while the monitor is in normal use
- The logfile reset is age-based, not size-based
- Keep the recovery target narrow and operationally safe for your environment
- For shared Komodo stacks, `WAIT_AFTER_GLUETUN_SECONDS` is not used because the
  stack restart is handled as one operation

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for script-specific change history.

## Transparency

The code, documentation, and related project materials in this repository were
created and refined with AI assistance. All generated output was reviewed and
adapted before publication.

## Maintainers

- [smoochy](https://github.com/smoochy)

## Contributing

Issues and pull requests are welcome. Keep changes focused on reliable host-side
automation, predictable maintenance behavior, testing, and documentation that
reflects real operational requirements.

## License

[MIT](../../../../LICENSE) 2026 [smoochy](https://github.com/smoochy)
