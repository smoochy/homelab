# Radarr Auto Tag and Deferred Cleanup for Tautulli

This automation helper applies watched-state handling in Radarr and schedules
deferred movie file cleanup through a persistent queue.

It is designed to work safely with Tautulli's `Stop` trigger and then
independently verifies the actual watch progress from Tautulli before touching
Radarr.

## Table of Contents

- [Background](#background)
- [Features](#features)
- [Files](#files)
- [Configuration](#configuration)
- [Install](#install)
- [Usage](#usage)
- [Transparency](#transparency)
- [Maintainers](#maintainers)
- [Queue Behavior](#queue-behavior)
- [Playback Scenarios](#playback-scenarios)
- [Cron Example](#cron-example)
- [Verification](#verification)
- [Notes](#notes)
- [Contributing](#contributing)
- [License](#license)

## Background

Tautulli can trigger scripts when playback stops, but that event alone is not a
safe signal for changing library state. This script uses Tautulli as the source
of truth, validates the final watch progress from Tautulli data, and then
updates Radarr only when the movie was actually watched far enough.

## Features

- Uses the Plex `rating_key` from Tautulli
- Persists delayed deletions in `radarr_movie.pending.json`
- Supports queue-only processing with `--run-pending`
- Loads configuration from container environment variables
- Also loads a local `.env` file next to the script for manual runs
- Supports overriding the `.env` path with `AUTO_TAG_ENV_FILE`
- Falls back to the Python standard library when `requests` is not installed
- Works well in Linux-based Tautulli containers and on Unraid hosts
- Reads the movie watched threshold directly from Tautulli's `config.ini`
- Verifies the last completed movie session from Tautulli's `tautulli.db`
- Prevents false-positive cleanup runs caused by bad initial resume offsets
- Handles multi-session movie watching safely

## Files

- `radarr_movie.py`: main script
- `.env.example`: example environment file
- `radarr_movie.pending.json`: persistent deletion queue
- `radarr_movie.pending.json.lock`: advisory queue lock file used on platforms
  with `fcntl` support

## Configuration

The script reads these environment variables:

- `RADARR_URL`
- `RADARR_API_KEY`
- `PLEX_URL`
- `PLEX_TOKEN`
- `WATCHED_TAG_LABEL`
- `KEEP_TAG_LABEL`
- `DELETION_DELAY_SECONDS`
- `REQUEST_TIMEOUT_SECONDS`
- `TAUTULLI_CONFIG_PATH` (optional)
- `TAUTULLI_DB_PATH` (optional)
- `SESSION_WAIT_SECONDS` (optional)
- `SESSION_LOOKBACK_HOURS` (optional)
- `AUTO_TAG_ENV_FILE` (optional)

Typical values:

```env
RADARR_URL=http://radar:7878
RADARR_API_KEY=your_radarr_api_key
PLEX_URL=http://plex:32400
PLEX_TOKEN=your_plex_token
WATCHED_TAG_LABEL=watched
KEEP_TAG_LABEL=keep
DELETION_DELAY_SECONDS=7200
REQUEST_TIMEOUT_SECONDS=10
```

Notes:

- `RADARR_URL` and `RADARR_API_KEY` are always required
- `PLEX_URL` and `PLEX_TOKEN` are required for normal watch-event runs
- `PLEX_URL` and `PLEX_TOKEN` are not required for `--run-pending`
- `TAUTULLI_CONFIG_PATH` defaults to the local Tautulli `config.ini`
- `TAUTULLI_DB_PATH` defaults to the local Tautulli `tautulli.db`
- `SESSION_WAIT_SECONDS` controls how long the script waits for the just-stopped
  Tautulli session to appear in the database
- `SESSION_LOOKBACK_HOURS` limits how far back the script searches for the last
  completed movie session
- If present, a local `.env` file is loaded automatically from the script
  directory
- `AUTO_TAG_ENV_FILE` can point to a different `.env` file for manual runs
- Tautulli does not load `.env` files by itself. For container use, inject the
  variables through your Compose stack or container configuration

## Install

### Prerequisites

- Tautulli is installed and connected to Plex
- Radarr is running and API access is enabled
- You know your Plex token
- `radarr_movie.py` is available inside the Tautulli container
- The required environment variables are available to the script

Plex token reference:
[Finding an authentication token / X-Plex-Token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/)

### 1. Create the Radarr tags

Create these tags in Radarr before using the script:

- `watched`
- `keep`

`watched` is required. `keep` is used to prevent unmonitoring and deletion for
selected movies.

### 2. Place the script

Recommended Tautulli path:

```bash
/config/scripts/auto_tag/
```

Copy these files there:

- `radarr_movie.py`
- `.env.example` as your template for environment values

### 3. Provide configuration

Recommended container-based approach:

1. Copy the values from `.env.example`.
2. Add them to your Tautulli Compose stack or referenced env file.
3. Recreate or redeploy the Tautulli container.

Optional manual-run approach:

1. Keep a `.env` file next to `radarr_movie.py`.
2. Or set `AUTO_TAG_ENV_FILE` to another env file path.

### 4. Configure the Tautulli notification agent

1. Open Tautulli.
2. Go to `Settings > Notification Agents`.
3. Add a new agent of type `Script`.
4. In `Configuration`, set the script folder to:

```bash
/config/scripts/auto_tag/
```

5. Select `radarr_movie.py`.
6. In `Triggers`, enable `Stop`.
7. In `Conditions`, add:

- `Media Type is not Episode`

8. In `Arguments`, use:

```bash
{rating_key}
```

9. Save the notification agent.

The script still accepts optional title and year override arguments:

```bash
python3 radarr_movie.py <rating_key> [title] [year]
```

For the normal Tautulli workflow, only `{rating_key}` is needed.

### 5. Keep Tautulli as the Single Source of Truth

The script reads `movie_watched_percent` directly from Tautulli:

- [config.ini](/mnt/user/appdata/tautulli/config.ini#L133)

You only need to change the movie watched threshold in Tautulli.

Recommended:

- Plex: `Settings > Library > Video played threshold`
- Tautulli: `Settings > General > Movie Watched Percentage`

Plex and Tautulli should still use matching watched thresholds so Plex's
internal markers and Tautulli's final validation agree.

### 6. Optional Queue Processing Schedule

If you want queued deletions processed without waiting for the next watch event,
schedule:

```bash
docker exec tautulli python3 /config/scripts/auto_tag/radarr_movie.py --run-pending
```

## Usage

### Handle a Watch Event

```bash
python3 /config/scripts/auto_tag/radarr_movie.py <rating_key>
```

Optional override arguments:

```bash
python3 /config/scripts/auto_tag/radarr_movie.py <rating_key> "<title>" <year>
```

### Process Pending Deletions Only

```bash
python3 /config/scripts/auto_tag/radarr_movie.py --run-pending
```

From the Unraid host, the recommended command is:

```bash
docker exec tautulli python3 /config/scripts/auto_tag/radarr_movie.py --run-pending
```

## Transparency

The code, documentation, and related project materials in this repository were
created and refined with AI assistance. All generated output was reviewed and
adapted before publication.

## Maintainers

- [smoochy](https://github.com/smoochy)

## Queue Behavior

- Queue data is stored in `radarr_movie.pending.json`
- Entries survive Tautulli container restarts
- New queue entries replace older entries for the same `file_id`
- Queue timestamps are stored in UTC
- Log timestamps are shown in local time
- If Radarr has already removed the file, the queue entry is treated as done on
  the next run

Current queue payload format:

```json
{
  "version": 1,
  "tasks": [
    {
      "created_at": "2026-03-08T12:00:00+00:00",
      "delete_after": "2026-03-08T14:00:00+00:00",
      "file_id": 123,
      "movie_id": 456,
      "title": "Example Movie",
      "year": 2024
    }
  ]
}
```

## Playback Scenarios

The examples below use an anonymized movie title: `Example Movie`.

### Scenario 1: Movie Stopped Too Early

Example:

- You stop `Example Movie` after 35%.
- Tautulli fires the `Stop` trigger.
- The script reads the latest completed Tautulli session.
- The script sees that the progress is below `movie_watched_percent`.
- No Radarr tag is added.
- No unmonitoring happens.
- No deletion is queued.

Typical log output:

```text
[INFO] Tautulli session 123 verification for 'Example Movie (2024) [ratingKey 1748]': 35.00% watched using Tautulli's movie_watched_percent=95%.
[INFO] Watched verification failed for 'Example Movie (2024) [ratingKey 1748]'. Required 95% but only 35.00% was recorded. Skipping Radarr changes.
```

### Scenario 2: Movie Watched Over Multiple Sessions

Example:

- First stop at 40%.
- Second stop at 72%.
- Third stop at 97%.

Behavior:

- First stop: script runs and exits without Radarr changes.
- Second stop: script runs and exits without Radarr changes.
- Third stop: script runs, verifies that the latest completed session reached
  the Tautulli threshold, and then applies the Radarr workflow.

This means you can watch a movie in multiple sittings without having to disable
automation.

### Scenario 3: False Watched Signal from Plex or the Client

Example:

- The playback client briefly reports a bad resume position near the end of
  `Example Movie`.
- Tautulli might otherwise consider the movie watched too early.

Behavior now:

- The script does not trust the raw trigger alone.
- It waits for the completed Tautulli session row in `tautulli.db`.
- It checks the stored `view_offset` against the full movie duration.
- If the recorded progress is below Tautulli's configured watched threshold,
  Radarr changes are skipped.

This is the main protection against false-positive tag and delete runs.

### Scenario 4: Movie Watched Normally

Example:

- You stop `Example Movie` at or above the Tautulli movie watched percentage.
- The script verifies the last completed session.
- The movie is matched in Radarr.
- The `watched` tag is applied.
- If there is no `keep` tag, the movie is unmonitored and the file deletion is
  queued.

Typical log output:

```text
[INFO] Tautulli session 124 verification for 'Example Movie (2024) [ratingKey 1748]': 97.12% watched using Tautulli's movie_watched_percent=95%.
[INFO] Tag 'watched' applied to 'Example Movie (2024)' & unmonitored.
[INFO] 'Example Movie (2024)' queued for deletion at 14.03.2026 23:15:00 CET+0100.
```

### Scenario 5: Keep Tag Present

Example:

- `Example Movie` is watched above the threshold.
- The matching Radarr movie already has the `keep` tag.

Behavior:

- The `watched` tag is still applied.
- `monitored` stays unchanged.
- No deletion is queued.

## Cron Example

Daily at `04:00`:

```cron
0 4 * * * docker exec tautulli python3 /config/scripts/auto_tag/radarr_movie.py --run-pending
```

If you want deletions to happen closer to `DELETION_DELAY_SECONDS`, use a more
frequent schedule such as every 5 or 10 minutes.

## Verification

After watching a movie past the configured watched threshold:

- Tautulli should show the script run in its logs
- Movies with the `keep` tag should be tagged as watched and not queued for deletion
- Movies without the `keep` tag should be tagged, unmonitored, and queued

Example log output when a movie is kept:

![Tautulli log when a movie is kept](assets/example_keep.png)

Example log output when a movie is queued for deletion:

![Tautulli log when a movie is queued for deletion](assets/example_delete.png)

## Notes

- The script exits with an error if the configured watched tag does not exist in Radarr
- If the keep tag does not exist, the script cannot use it to protect movies from deletion
- If no `movieFile` is present in Radarr, the script skips deletion

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for script-specific change history.

## Contributing

Issues and pull requests are welcome. Keep changes focused on reliable Tautulli
and Radarr automation and update the README when behavior changes.

## License

[MIT](../../../../LICENSE) 2026 [smoochy](https://github.com/smoochy)
