# Changelog

## 2026-08-20

### Added
- A file allowlist over the staged link farm (#1120, #1121). Only video, subtitles and the original NFO reach upPollo and the seed volume; everything else, plus anything carrying `sample` anywhere in its path, is unlinked and the directories left empty are pruned. A release with no surviving video file is not staged at all and reports to Discord through Apprise as a warning, in the runner's payload shape.
- `test_uppollo_stage.sh`, a self-check that runs the script over a fabricated job directory and a fake `wget`.

## 2026-08-18

### Added
- First release. Stages a successful SABnzbd job for upPollo by building a hardlink farm of the finished directory under its original release name, so the name survives the media managers' rename and deletion. The entry is built under `.incoming` and moved into place, which is atomic within one filesystem, and a staging root on a different filesystem is refused rather than silently turned into a full copy.
