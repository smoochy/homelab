#!/usr/bin/env bash
# Self-check for uppollo_stage.sh. Runs the script against a fabricated SABnzbd
# job directory and a fake wget that records the Apprise payload, so the
# allowlist, the sample rule, the empty-directory pruning and the no-video case
# are exercised without SABnzbd, a staging tree or a notifier. Run from this
# directory: bash test_uppollo_stage.sh
set -eu

script="$(cd "$(dirname "$0")" && pwd)/uppollo_stage.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The fake stands in for the Apprise POST and records the body it was handed, so
# a test can assert that a case notified at all. jq is left real: the payload
# shape is part of what is under test.
mkdir -p "$work/bin"
cat > "$work/bin/wget" <<'FAKE'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in --post-data=*) printf '%s\n' "${arg#--post-data=}" >> "$NOTIFY_LOG" ;; esac
done
exit 0
FAKE
chmod +x "$work/bin/wget"
PATH="$work/bin:$PATH"
NOTIFY_LOG="$work/notify.log"
: > "$NOTIFY_LOG"
export PATH NOTIFY_LOG

export UPPOLLO_STAGING_ROOT="$work/staging"
export APPRISE_ENDPOINT="http://apprise.invalid/notify/test"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Builds a job directory and runs the script over it as SABnzbd would, with the
# category fixed to `radarr` and the status to success.
stage() {
    release="$1"
    shift
    mkdir -p "$work/complete/$release"
    for entry in "$@"; do
        mkdir -p "$work/complete/$release/$(dirname "$entry")"
        echo x > "$work/complete/$release/$entry"
    done
    "$script" "$work/complete/$release" "$release" "$release" 0 radarr grp 0 > "$work/log.txt" 2>&1
}

# A release carrying the whole usenet zoo: the video and its subtitle survive,
# the scene NFO survives, the par2/sfv/nzb/txt remnants go, and the sample goes
# whatever its extension - which is why it is an .mkv here.
stage "Some.Movie.2026.1080p-GRP" \
    "Some.Movie.2026.1080p-GRP.mkv" \
    "Some.Movie.2026.1080p-GRP.srt" \
    "some.movie.nfo" \
    "Some.Movie.2026.1080p-GRP.nzb" \
    "Some.Movie.2026.1080p-GRP.par2" \
    "Some.Movie.2026.1080p-GRP.sfv" \
    "readme.txt" \
    "Sample/some-movie-sample.mkv" \
    "proof/proof.jpg"

target="$UPPOLLO_STAGING_ROOT/radarr/Some.Movie.2026.1080p-GRP"
[ -d "$target" ] || fail "the release was not staged"

survivors="$(cd "$target" && find . -type f | sort | tr '\n' ' ')"
expected="./Some.Movie.2026.1080p-GRP.mkv ./Some.Movie.2026.1080p-GRP.srt ./some.movie.nfo "
[ "$survivors" = "$expected" ] || fail "unexpected survivors: $survivors"

# The sample and proof directories held nothing else, so they are gone rather
# than left behind as empty shells.
[ -d "$target/Sample" ] && fail "the empty Sample directory was not pruned"
[ -d "$target/proof" ] && fail "the empty proof directory was not pruned"
[ -s "$NOTIFY_LOG" ] && fail "a healthy release must not notify"

# A release whose only video is a sample: nothing survives the filter, so the
# entry is dropped before it can ever become visible to the runner.
stage "Broken.Release.2026-GRP" \
    "broken-sample.mkv" \
    "Broken.Release.2026-GRP.par2" \
    "readme.nfo"

[ -e "$UPPOLLO_STAGING_ROOT/radarr/Broken.Release.2026-GRP" ] && fail "a release without a video was staged"
[ -e "$UPPOLLO_STAGING_ROOT/.incoming/radarr/Broken.Release.2026-GRP" ] && fail ".incoming was left behind"
grep -q '"type": *"warning"' "$NOTIFY_LOG" || fail "the empty case did not notify as a warning"
grep -q 'Broken.Release.2026-GRP' "$NOTIFY_LOG" || fail "the notification does not name the release"

echo "OK"
