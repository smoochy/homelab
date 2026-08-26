# Changelog

## 2026-08-24

### Added
- Removals are sorted into three buckets (#331). A sample or proof and a known usenet remnant - the new `UPPOLLO_KNOWN_JUNK_EXTENSIONS`, the `r00`-`r999` volumes and the `.DS_Store` / `._*` / `__MACOSX` names - go silently, as before. Anything else is still removed, but its relative path is written to the job log and named in one Apprise message, because an unexplained removal is the one case where the allowlist may be eating something the tracker wanted.

- An "incomplete, trumpable" marker (#331), reported through the log and the same message: an archive (`rar`, `r00`-`r999`, `zip`, `7z`) in the job means the payload was packed and only the unpacked part survives, and a directory that held files before the filter and is empty afterwards means a whole part of the release is gone. The second needs a snapshot taken before the removal loop; afterwards an emptied directory and one that arrived empty are indistinguishable. A `Sample` or `Proof` directory is skipped, or every healthy release would report itself. Neither case aborts, and a job sends at most one Apprise message: the unexpected removals and the incompleteness travel together, and the existing no-video-survived abort keeps its own.

- The doubled release directory an obfuscated NZB leaves behind is collapsed before the entry is staged (#1379). The rule matches only that shape - exactly one subdirectory, named like the release, with nothing beside it - so `Subs`, season pack episodes, `BDMV` and `VIDEO_TS` are left as they arrived. A name present on both levels is not collapsed and reports a `[WARN]` line instead. RocketHD rejects the nested structure: an upload staged this way was removed by the mod team within the hour on 2026-08-24.

- The NFO a staged release ships is verified against srrDB before the entry is moved into place. srrDB knows the exact release name and holds a top-level `.nfo`: that file replaces whatever the job carried. srrDB does not know the release, or knows it without an NFO: the local file cannot be vouched for and is removed, which is the P2P case the tracker permits. The lookup failing is not a verdict and leaves the entry as it arrived. A MediaInfo dump named after the release got an upload removed by the mod team on 2026-08-24, with the staff reason that this group embeds its NFO in the MKV if at all.

### Changed
- `requests` added to the default `UPPOLLO_STAGED_CATEGORIES`, which is what the host has been running.

## 2026-08-20

### Added
- A file allowlist over the staged link farm (#1120, #1121). Only video, subtitles and the original NFO reach upPollo and the seed volume; everything else, plus anything carrying `sample` anywhere in its path, is unlinked and the directories left empty are pruned. A release with no surviving video file is not staged at all and reports to Discord through Apprise as a warning, in the runner's payload shape.
- `test_uppollo_stage.sh`, a self-check that runs the script over a fabricated job directory and a fake `wget`.

## 2026-08-18

### Added
- First release. Stages a successful SABnzbd job for upPollo by building a hardlink farm of the finished directory under its original release name, so the name survives the media managers' rename and deletion. The entry is built under `.incoming` and moved into place, which is atomic within one filesystem, and a staging root on a different filesystem is refused rather than silently turned into a full copy.
