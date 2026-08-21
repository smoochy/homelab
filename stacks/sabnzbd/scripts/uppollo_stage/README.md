# upPollo Staging Post-Processing Script

This post-processing helper stages a finished SABnzbd job for upPollo, so that usenet-sourced releases reach the private tracker as either a new upload or a cross-seed.

It is intended to be used as a SABnzbd post-processing script and works inside Docker-based SABnzbd setups such as Unraid.

## Table of Contents

- [Background](#background)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Configuration](#configuration)
- [Failure handling](#failure-handling)

## Background

The tracker requires the original release name. Radarr and Sonarr rename the file on import and then delete the completed download, so that name exists only in the moment between download completion and import - after which nothing on disk carries it any more.

This script captures that moment. On a successful job it builds a link farm of the finished directory under its original name inside the staging tree, and the `uppollo-runner` rider in the `qbittorrent` stack picks it up from there and invokes upPollo on it.

Links, not copies: the staging tree and the completed download live on the same array, so the staged entry costs no space and the media managers may delete their own copy at will. Directories cannot be hardlinked, which is why this is a recursive link farm (`cp -al`) rather than a single `ln`.

The entry is built under `.incoming` and moved into place afterwards. A rename within one filesystem is atomic, so the runner can never observe a half-built directory and neither side needs a lock.

## Requirements

- SABnzbd with post-processing scripts enabled. The linuxserver image ships `bash`, GNU `find`, `jq` and busybox `wget`, which is everything the script uses - the busybox one is why the Apprise call passes `-T 10` rather than the runner's `--timeout=10`.
- A staging root on the same filesystem as the completed downloads. A different filesystem would silently turn the link farm into a full copy; the script checks the link count afterwards and refuses rather than staging a copy.
- The `uppollo-runner` service of the `qbittorrent` stack, which consumes the staging tree. That rider also creates the staging tree and hands every directory it creates to the share user, because it runs as root while this script runs as SABnzbd's `PUID`/`PGID`. A root-owned `0755` staging directory is the failure this cost a day to find: every job logged `cp: cannot create directory ...: Permission denied` and nothing ever reached the runner, while both halves looked healthy.
- SABnzbd's `replace_dots` switch off (`Config > Switches`, or `replace_dots = 0` in `sabnzbd.ini`). It is untracked host state. With it on, SABnzbd rewrites every dot in the job name as a space, so `DDP5.1` arrives as `DDP5 1`. The change is lossy, so no later step can rebuild the original name, and upPollo's duplicate check scores by name similarity - a mangled name costs matches for nothing.

## Install

The script lives in SABnzbd's scripts directory, which the stack mounts from `/mnt/user/appdata/sabnzbd/scripts`:

```sh
install -m 755 uppollo_stage.sh /mnt/user/appdata/sabnzbd/scripts/uppollo_stage.sh
```

Then select it in SABnzbd under `Config > Categories` as the script for every category the media managers download into, or globally under `Config > Switches > Post-processing script`. On this host those are `sonarr` and `radarr` - the categories Sonarr and Radarr send by default - rather than the `tv` and `movies` categories they write into, so the category the script is handed is the sending application's, not the directory's.

## Usage

SABnzbd calls the script with its standard argument list; nothing has to be passed by hand. It stages only jobs that finished successfully and whose category is listed in `UPPOLLO_STAGED_CATEGORIES`, and it is a no-op for everything else.

The resulting layout, relative to the staging root:

```text
.incoming/<category>/<release>   being built, never picked up
<category>/<release>             complete, ready for the runner
failed/<category>/<release>      the runner's parking lot for a failed run
```

## Configuration

Both values are environment variables with working defaults; SABnzbd passes its own environment through to the script.

| Variable | Default | Meaning |
| --- | --- | --- |
| `UPPOLLO_STAGING_ROOT` | `/data/usenet/staging` | Where staged entries are written. Must be on the same filesystem as the completed downloads. |
| `UPPOLLO_STAGED_CATEGORIES` | `movies tv radarr sonarr` | Space-separated categories that are staged at all. Any other category completes untouched. A category that is not listed here is the one way this silently does nothing, so it has to match what SABnzbd actually reports, which is the category name and not the download directory. |
| `UPPOLLO_VIDEO_EXTENSIONS` | `mkv mp4 avi ts m2ts` | Space-separated video extensions. Part of the allowlist, and separately the answer to whether the release still has anything worth seeding after filtering. |
| `UPPOLLO_EXTRA_EXTENSIONS` | `srt sub idx ass ssa nfo` | Space-separated non-video extensions that may travel with the release. |
| `APPRISE_ENDPOINT` | empty | Where the empty case is reported. Empty disables notifications; the script never fails a job over a notifier. |

## The allowlist

The staging tree mirrors the whole SABnzbd job directory, so `.nzb`, `.par2`, `.sfv`, `sample/`, `proof/`, `.txt` and `.url` would otherwise travel with the release onto the seed volume. upPollo's own `TorrentExcludePatterns` do not help: they act on torrent creation only and say nothing about what `link_mode: copy` writes into `/seed/uploads`.

So the script filters the link farm right after building it and before moving it into place. Only the three classes RocketHD permits survive - video, subtitles, the original scene NFO - plus a name rule alongside them: anything carrying `sample` anywhere in its path goes, whatever its extension, because an extension allowlist happily passes `release-sample.mkv`. It is an allowlist rather than a denylist so that a usenet habit nobody has seen yet is excluded by default rather than by amendment. Paths are matched relative to the release root, so a release whose own name contains `sample` does not delete itself.

The structure is kept as the release had it, only files are removed and directories left empty afterwards are pruned. Flattening would deviate from the original release, which is exactly what the tracker's duplicate comparison and the `seed_on_dupe` hash reuse read.

The filter runs before the duplicate verdict exists, so the cross-seed path inherits it. That is a knowing cost: if a fetched tracker torrent contains a `.txt` the allowlist removed, the local verify comes up short and qBittorrent pulls those few KB from the swarm.

If no video file survives, nothing is staged at all - `.incoming` is removed and the release never becomes visible to the runner, which is what upPollo would have concluded anyway with `packed release detected`. The case is not silent: it reports to Discord through Apprise as a `warning`, in the runner's payload shape.

## Tests

`bash test_uppollo_stage.sh`, from this directory. It builds a fabricated job directory and a fake `wget`, then asserts the survivors, the pruning and the no-video notification. It needs `jq` and GNU `find`.

## Failure handling

The script never fails a SABnzbd job for its own reasons: an unsuccessful job, an unknown category or a release that is already staged all exit cleanly and leave the job alone. A staging root on the wrong filesystem, an unusable final directory or a failed link farm exit non-zero and are visible in SABnzbd's script log, with the half-built entry removed.

What happens to a staged release afterwards belongs to the runner, which logs to the `qbittorrent-uppollo-runner` container and notifies through Apprise on a failure.
