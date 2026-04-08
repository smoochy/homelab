# SABnzbd History Cleanup Scripts

These scripts automate cleanup of completed SABnzbd history entries for
selected categories.

The workflow is split into two parts:

- `delete_item.sh` runs as a SABnzbd post-processing script and queues matching jobs
- `delete_items_worker.sh` runs on the Docker host and deletes the queued items
  from SABnzbd history through the local API

## Table of Contents

- [Background](#background)
- [Features](#features)
- [Requirements](#requirements)
- [Files](#files)
- [Configuration](#configuration)
- [Install](#install)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Notes](#notes)
- [Transparency](#transparency)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

SABnzbd keeps completed jobs in history even when those entries are only
temporary operational data for some categories. These scripts let you queue and
remove those history entries automatically after successful jobs.

## Features

- Deletes successful history entries only
- Filters by one or more SABnzbd categories
- Resolves either an `nzo_id` or a job name from the queue
- Uses a queue file so post-processing stays fast
- Supports HTTP and HTTPS SABnzbd API setups

## Requirements

- SABnzbd running in Docker
- A writable shared queue location available to both the container and the host
- `curl` available inside the SABnzbd container
- `docker` available on the host for the worker script

## Files

- `delete_item.sh`: post-processing script executed by SABnzbd
- `delete_items_worker.sh`: host-side worker that processes the queue
- `delete_item.queue`: created automatically and used as a queue, preferably beside `sabnzbd.ini`

## Configuration

Open `delete_item.sh` and adjust these values:

- `DELETE_CATEGORIES="mhh"`: comma-separated categories that should be deleted
  from history
- `SAB_CONTAINER_NAME="sabnzbd"`: Docker container name of your SABnzbd instance

## Install

### 1. Map the script directory

- Host path: `/mnt/user/appdata/{sabnzbd}/scripts`
- Container path: `/scripts`
- Access: Read/Only or Read/Write

Restart the container afterwards.

### 2. Copy the scripts

Place both scripts in the mapped scripts directory:

- `/mnt/user/appdata/{sabnzbd}/scripts/delete_item.sh`
- `/mnt/user/appdata/{sabnzbd}/scripts/delete_items_worker.sh`

### 3. Convert to LF line endings

If the files were created or edited on Windows, convert them to LF:

```sh
sed -i 's/\r$//' /mnt/user/appdata/{sabnzbd}/scripts/delete_item.sh
sed -i 's/\r$//' /mnt/user/appdata/{sabnzbd}/scripts/delete_items_worker.sh
```

### 4. Make both scripts executable

```sh
chmod +x /mnt/user/appdata/{sabnzbd}/scripts/delete_item.sh
chmod +x /mnt/user/appdata/{sabnzbd}/scripts/delete_items_worker.sh
```

### 5. Configure SABnzbd

1. Go to `Config` -> `Folders`.
2. Set `User Script Folder` to `/scripts`.
3. Go to `Config` -> `Categories`.
4. Assign `delete_item.sh` to the category or categories you want to handle.

Only successful jobs in the configured categories are queued.

### 6. Schedule the worker on the host

Run `delete_items_worker.sh` regularly on the Docker host, for example with
cron or the Unraid User Scripts plugin.

Example cron entry:

```cron
*/5 * * * * /mnt/user/appdata/{sabnzbd}/scripts/delete_items_worker.sh
```

## Usage

- SABnzbd triggers `delete_item.sh` for completed jobs in configured categories
- The worker processes the shared queue file and performs the actual history deletion

## How It Works

1. SABnzbd finishes a download successfully.
2. `delete_item.sh` checks whether the category matches `DELETE_CATEGORIES`.
3. If it matches, the script appends the job identifier and API details to `delete_item.queue`, preferring the SABnzbd config directory and falling back to the script directory only when needed.
4. `delete_items_worker.sh` reads the queue and deletes the matching entries from SABnzbd history.

## Notes

- The worker uses a lock directory so only one instance runs at a time
- If a delete request fails, the item is requeued
- `delete_item.sh` expects SABnzbd's config at `/config/sabnzbd.ini`
- The default shared queue path is `/config/delete_item.queue` on the container side, which maps to `/mnt/user/appdata/{sabnzbd}/delete_item.queue` on the host

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for script-specific change history.

## Transparency

The code, documentation, and related project materials in this repository were
created and refined with AI assistance. All generated output was reviewed and
adapted before publication.

## Maintainers

- [smoochy](https://github.com/smoochy)

## Contributing

Issues and pull requests are welcome. Keep changes focused on reliable queueing
and history cleanup behavior and update the README when configuration or runtime
requirements change.

## License

[MIT](../../../../LICENSE) 2026 [smoochy](https://github.com/smoochy)
