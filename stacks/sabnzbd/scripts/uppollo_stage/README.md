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

The script itself lives at `stacks/qbittorrent/scripts/sabnzbd/uppollo_stage.sh` in this repository, in the shared script tree the `qbittorrent` and `sabnzbd` stacks both mount (#343). A Komodo Repo resource mirrors that tree onto `/mnt/user/appdata/qbittorrent/scripts` on every push, so nothing is installed by hand: a merged change reaches the next job on its own, and SABnzbd's `script_dir` points at `/scripts/current/sabnzbd` inside the mount so the mirror's revision swap is resolved per job.

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
| `UPPOLLO_STAGED_CATEGORIES` | `movies tv radarr sonarr requests` | Space-separated categories that are staged at all. Any other category completes untouched. A category that is not listed here is the one way this silently does nothing, so it has to match what SABnzbd actually reports, which is the category name and not the download directory. **`season-pack` must never be added**, see below. |
| `UPPOLLO_VIDEO_EXTENSIONS` | `mkv mp4 avi ts m2ts` | Space-separated video extensions. Part of the allowlist, and separately the answer to whether the release still has anything worth seeding after filtering. |
| `UPPOLLO_EXTRA_EXTENSIONS` | `srt sub idx ass ssa sup vtt smi mks nfo` | Space-separated non-video extensions that may travel with the release. |
| `UPPOLLO_KNOWN_JUNK_EXTENSIONS` | `par2 sfv nzb rar srr srs md5 txt url diz jpg jpeg png webp xml mp3 flac wav aac m4a ogg wma` | Space-separated extensions whose removal is expected and therefore silent. Anything else the allowlist removes is named in the log and in one Apprise message. |
| `APPRISE_ENDPOINT` | empty | Where the empty case, an unexpected removal and an incomplete release are reported. Empty disables notifications; the script never fails a job over a notifier. |

## The one category that must never be staged

`season-pack` is the category the `season-scan` rider of the `qbittorrent` stack grabs into, and it must never appear in `UPPOLLO_STAGED_CATEGORIES` (issues #1201, #1203). Its jobs are episodes of one season that are meant to become a single season pack: the rider waits until every job of the season has completed, assembles them into one pack directory on the seed volume, and deletes the downloads afterwards. Staging them would hand each episode to `uppollo-runner` as a release of its own, so the season would be uploaded episode by episode before the pack exists - and the pack would then be a duplicate of uploads the tracker already holds.

The default leaves it out, but only by omission. It is written down here because the failure is silent in both directions: nothing errors, the episodes simply go up one at a time.

## The allowlist

The staging tree mirrors the whole SABnzbd job directory, so `.nzb`, `.par2`, `.sfv`, `sample/`, `proof/`, `.txt` and `.url` would otherwise travel with the release onto the seed volume. upPollo's own `TorrentExcludePatterns` do not help: they act on torrent creation only and say nothing about what `link_mode: copy` writes into `/seed/uploads`.

So the script filters the link farm right after building it and before moving it into place. Only the three classes RocketHD permits survive - video, subtitles, the original scene NFO - plus a name rule alongside them: a path component named `sample` or `proof`, or a basename ending in `-sample`, `.sample` or `_sample` before its extension, goes whatever its extension, because an extension allowlist happily passes `release-sample.mkv`. It is a token match rather than a substring one, so an episode whose own title carries the word - `The.Sample.S01E01` - is a legitimate release and survives. It is an allowlist rather than a denylist so that a usenet habit nobody has seen yet is excluded by default rather than by amendment. Paths are matched relative to the release root, so a release whose own name contains `sample` does not delete itself.

Removals come in three buckets. A sample or proof goes silently, and so does a known usenet remnant - `UPPOLLO_KNOWN_JUNK_EXTENSIONS`, the `r00`-`r999` volumes and the `.DS_Store` / `._*` / `__MACOSX` names. Anything else is removed too, but its relative path is written to the job log and named in one Apprise message: an allowlist can only stay honest if what it silently eats is known, and an unexplained removal is the one case where it may be eating something the tracker wanted.

## Incomplete, trumpable

A release can reach the tracker missing something it shipped with, and an upload of the complete release then trumps it. Two signals say so, both reported through the job log and the same Apprise message as an unexpected removal:

- The job carried an archive (`rar`, `r00`-`r999`, `zip`, `7z`). RocketHD rejects packed content, so what is left after the filter is the unpacked part alone.
- A directory that held files before the filter is empty afterwards, so a whole part of the release is gone. This needs a snapshot taken before the removal loop: afterwards an emptied directory and one that arrived empty look the same. A `Sample` or `Proof` directory is skipped - the filter emptying that one is the rule working rather than a loss.

Neither aborts: the release is staged either way, and the decision whether to upload it belongs to whoever reads the message. The no-video-survived case is the one that still drops the entry entirely.

A job sends at most one Apprise message. An unexpected removal and an incomplete release travel in the same message, and a job that never lands reports only that.

The structure is kept as the release had it, only files are removed and directories left empty afterwards are pruned. Flattening would deviate from the original release, which is exactly what the tracker's duplicate comparison and the `seed_on_dupe` hash reuse read.

The filter runs before the duplicate verdict exists, so the cross-seed path inherits it. That is a knowing cost: if a fetched tracker torrent contains a `.txt` the allowlist removed, the local verify comes up short and qBittorrent pulls those few KB from the swarm.

If no video file survives, nothing is staged at all - `.incoming` is removed and the release never becomes visible to the runner, which is what upPollo would have concluded anyway with `packed release detected`. The case is not silent: it reports to Discord through Apprise as a `warning`, in the runner's payload shape.

## The doubled release directory

An obfuscated NZB arrives under a placeholder name and carries the real release name inside it, so SABnzbd names the job directory after the release and unpacks the payload into a second directory of the same name inside it. The staged entry then reads `<release>/<release>/<release>.mkv` while every release the tracker has ever seen has its files at the top level. RocketHD requires the original folder structure and rejects the upload otherwise: measured on 2026-08-24, when a release staged this way was uploaded and removed by the mod team within the hour (#1379).

So exactly that one shape is collapsed, right after the allowlist has run and before the entry is moved into place. The condition is the narrowest one that still describes the artefact: exactly one subdirectory, its name equal to the release name, and no other directory beside it. Anything a release brings itself - `Subs`, a season pack's episode files, `BDMV`, `VIDEO_TS`, `CD1`/`CD2` - fails at least one of those and is left exactly as it arrived, which is what the previous section means by keeping the structure as the release had it.

A name that exists on both levels is not resolvable here: one of the two files would have to be renamed or dropped, and the tracker rejects both. The entry is then staged nested as it is, with a `[WARN]` line in the SABnzbd job log naming the colliding entry, so the run reports rather than silently producing a structure nobody chose.

## The NFO

RocketHD wants the original NFO of the release and rejects an upload that carries something else under that name. A usenet job frequently ships a MediaInfo dump named `<release>.nfo`, and that is what got an upload removed on 2026-08-24: the staff reason was that this group embeds its NFO in the MKV if at all, so the file beside it can only be a fabrication.

Nothing about an NFO file tells you whether it is the original, so the release name is asked instead. srrDB stores scene releases under their exact name together with the file list they shipped, which makes it the one source that can confirm an NFO belongs to *this* release, not to a similarly named one.

So right before the entry is moved into place, `https://api.srrdb.com/v1/details/<release>` is queried:

- srrDB knows the release and holds a top-level `.nfo`: that file is downloaded from `https://www.srrdb.com/download/file/<release>/<nfo>` and replaces whatever the job carried, under srrDB's own file name.
- srrDB does not know the release, or knows it without an NFO: nothing can vouch for the local file, so it is removed. This is the P2P case, and the tracker permits an upload without an NFO - the original NFO is mandatory only for scene releases, where an otherwise equal upload with one may trump an upload without.
- The lookup itself fails: the entry is staged exactly as it arrived. A dead API or a timeout must never be the reason a genuine scene NFO is deleted, and an upload with an NFO too many is a moderator's edit while an upload with the wrong NFO is a removal.

This needs `curl` in the SABnzbd image, which the linuxserver one ships.

## The name

The same lookup answers a second question. A scene release is vouched for by srrDB under its exact name, and upPollo restages it under srrDB's spelling anyway, so its name is checked twice before it reaches the tracker. A P2P or self-encoded release has no srrDB entry: it is staged under SABnzbd's job name, and nothing has ever looked at that name.

So for exactly those releases - and only for them, right before the entry is moved into place - CrowdNFO's public read API is asked once, `https://crowdnfo.net/api/releases` with the staged name as the search term. It is a crowd-submitted release database, so it is asked for agreement rather than for proof, and it decides nothing on its own: the check prints one word and every outcome still stages.

- The top hit agrees: nothing happens, and the job stays silent.
- CrowdNFO holds the release under our own group but a different name: the entry is staged and a marker is written beside it, `staging/<category>/.<release>.needs-review`. Dot-prefixed, so the runner's own glob does not see it - the upload is marked for a human, never withheld - and beside the entry rather than inside it, so it cannot travel to the tracker as part of the release.
- Anything else - no hit, an unreachable or rate-limited API, any non-200, or a top hit belonging to another group - is unconfirmed, and the release is staged with a warning. This is the fail-open case and it is the common one: CrowdNFO never claimed to be complete, and refusing here would drop the link farm of a genuine release for a database that does not know it.

Two details are measured rather than assumed. The `categories` parameter is comma-separated; the `Movies|TV` spelling answers 400, which would have turned every lookup into a silent unconfirmed. And a free-text search returns whatever matched, sorted by submission date, so the top hit is not necessarily this release - a search for `1080p` returns whatever was submitted last. A hit therefore has to prove it is talking about the same release before it may contradict the staged name: its release group has to be our release group. A hit from another group says nothing.

Comparison is agreement, not byte equality: lowercase, every scene separator to a space, runs of spaces collapsed. The entries are submitted by hand, so a dot where the release had a dash is the normal case and a byte-exact gate would reject on cosmetic drift alone.

The verdict travels in the same single Apprise message as an unexpected removal and an incomplete release, which is why that message is sent after this check rather than before it.

## Tests

`bash tests/test_uppollo_stage.sh`, from `stacks/qbittorrent/scripts/sabnzbd/` in the repository, where the script and its test live since #343. It builds a fabricated job directory, a fake `wget` and a fake `curl` serving a srrDB and a CrowdNFO fixture tree, then asserts the survivors, the pruning, the no-video notification, the widened subtitle set, the token sample rule, the unexpected-removal report, both incompleteness signals, the three doubled-directory cases, the three NFO cases and the four name cases. It needs `jq` and GNU `find`.

## Failure handling

The script never fails a SABnzbd job for its own reasons: an unsuccessful job, an unknown category or a release that is already staged all exit cleanly and leave the job alone. A staging root on the wrong filesystem, an unusable final directory or a failed link farm exit non-zero and are visible in SABnzbd's script log, with the half-built entry removed.

What happens to a staged release afterwards belongs to the runner, which logs to the `qbittorrent-uppollo-runner` container and notifies through Apprise on a failure.
