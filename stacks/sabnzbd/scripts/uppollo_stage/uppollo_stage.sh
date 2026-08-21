#!/usr/bin/env bash
# SABnzbd post-processing script that stages a finished job for upPollo
# (homelab-private issues #915, #923).
#
# The tracker requires the original release name, but Radarr and Sonarr rename
# the file on import and delete the completed download afterwards, so the name
# exists only between those two moments. This script captures it: it builds a
# link farm of the finished job under its own name and hands it to the runner in
# the qbittorrent stack, which invokes upPollo on it.
#
# Links, not copies - the staging tree and the completed download live on the
# same array, so `cp -al` costs nothing and the media managers may delete their
# own copy at will. Directories cannot be hardlinked, which is why this is a
# recursive link farm rather than a single `ln`.
#
# The farm mirrors the whole job directory, so it is filtered before it is moved
# into place: only what the tracker permits survives (#1120, #1121). That is the
# one moment where removing a file costs nothing and cannot touch the completed
# download the media managers still import from.
#
# The entry is built under .incoming and moved into place afterwards. A rename
# within one filesystem is atomic, so the runner can never observe a half-built
# directory and neither side needs a lock.
#
# Expected SABnzbd arguments:
# $1 = Final directory
# $2 = NZB name
# $3 = Job name
# $4 = Report number
# $5 = Category
# $6 = Group
# $7 = Status (0 = success)
# $8 = Password (optional)

FINAL_DIR="$1"
JOB_NAME="$3"
CATEGORY="$5"
STATUS="$7"

STAGING_ROOT="${UPPOLLO_STAGING_ROOT:-/data/usenet/staging}"
# Categories that reach the tracker at all. Everything else completes untouched.
STAGED_CATEGORIES="${UPPOLLO_STAGED_CATEGORIES:-movies tv radarr sonarr}"

# What may reach upPollo and the seed volume (#1120). An allowlist rather than a
# denylist, so a usenet habit nobody has seen yet is excluded by default rather
# than by amendment. The three classes RocketHD permits are split into video and
# the rest only because the empty case below has to ask whether a *video* file
# survived; the allowlist is their union.
VIDEO_EXTENSIONS="${UPPOLLO_VIDEO_EXTENSIONS:-mkv mp4 avi ts m2ts}"
EXTRA_EXTENSIONS="${UPPOLLO_EXTRA_EXTENSIONS:-srt sub idx ass ssa nfo}"

# Best effort, and the same payload shape the runner sends (#942), so the empty
# case shows up in the same Discord channel as every other upPollo outcome. A
# missing endpoint or a dead notifier never fails the SABnzbd job.
APPRISE_ENDPOINT="${APPRISE_ENDPOINT:-}"

echo "[INFO] === upPollo staging script started ==="
echo "[INFO] Final directory : $FINAL_DIR"
echo "[INFO] Job name        : $JOB_NAME"
echo "[INFO] Category        : $CATEGORY"
echo "[INFO] SAB status      : $STATUS"

# The payload is built with jq rather than by string interpolation, because the
# release name is scene free text and may carry quotes. `-T` rather than the
# runner's `--timeout=`: this container's wget is busybox, which knows only the
# short form, while the runner's is GNU.
notify_warning() {
    [[ -n "$APPRISE_ENDPOINT" ]] || return 0
    wget -q -O /dev/null -T 10 \
        --header='Content-Type: application/json' \
        --post-data="$(jq -n --arg title "⚠️ upPollo: nothing landed" --arg body "$1" \
            '{title: $title, body: $body, type: "warning", format: "markdown"}')" \
        "$APPRISE_ENDPOINT" || echo "[WARN] Apprise notification failed"
}

# Work only on successful jobs. A failed or repaired-out job has nothing to seed.
if [[ "$STATUS" != "0" ]]; then
    echo "[INFO] Job did not complete successfully, nothing staged"
    exit 0
fi

if [[ ! -d "$FINAL_DIR" ]]; then
    echo "[ERROR] Final directory does not exist: $FINAL_DIR"
    exit 1
fi

staged=false
for candidate in $STAGED_CATEGORIES; do
    if [[ "$candidate" == "$CATEGORY" ]]; then
        staged=true
        break
    fi
done

if [[ "$staged" != true ]]; then
    echo "[INFO] Category $CATEGORY is not staged for upPollo, nothing to do"
    exit 0
fi

# SABnzbd's job name is the original release name only while `replace_dots` is
# off. With it on, SABnzbd rewrites every dot as a space, and `DDP5.1` comes back
# as `DDP5 1` - lossy, so no later step can rebuild the name. Measured on
# 2026-08-19: upPollo still identified the release, but its dupe check scores by
# name similarity, so the mangled name costs matches for nothing. The setting is
# untracked host state and therefore recorded in the stack readme.
RELEASE="${JOB_NAME:-$(basename "$FINAL_DIR")}"
INCOMING="$STAGING_ROOT/.incoming/$CATEGORY/$RELEASE"
TARGET="$STAGING_ROOT/$CATEGORY/$RELEASE"

if [[ -e "$TARGET" ]]; then
    echo "[INFO] $RELEASE is already staged, leaving the existing entry alone"
    exit 0
fi

rm -rf "$INCOMING"
mkdir -p "$(dirname "$INCOMING")" "$(dirname "$TARGET")" || {
    echo "[ERROR] Could not create the staging tree under $STAGING_ROOT"
    exit 1
}

# -a keeps the tree structure and timestamps, -l makes every file a hardlink.
# A cross-device staging root would silently turn this into a full copy, so the
# link count is checked afterwards rather than assumed.
if ! cp -al "$FINAL_DIR" "$INCOMING"; then
    echo "[ERROR] Could not link $FINAL_DIR into $INCOMING"
    rm -rf "$INCOMING"
    exit 1
fi

probe="$(find "$INCOMING" -type f -print -quit)"
if [[ -n "$probe" && "$(stat -c '%h' "$probe")" -lt 2 ]]; then
    echo "[ERROR] $STAGING_ROOT is not on the same filesystem as $FINAL_DIR - refusing to stage a full copy"
    rm -rf "$INCOMING"
    exit 1
fi

# The allowlist (#1120), applied here rather than in the runner or in upPollo's
# own exclude patterns: the tree is a hardlink farm, so unlinking an entry costs
# nothing and never touches the completed download the media managers still
# import from, and upPollo's `TorrentExcludePatterns` act on torrent creation
# only - they say nothing about what `link_mode: copy` puts into /seed/uploads.
# It runs before the dupe verdict exists, so the seed_on_dupe cross-seed
# inherits the same rule.
#
# Paths are matched relative to the release root, so a release whose own name
# happens to contain "sample" does not delete itself. The structure is kept as
# the release had it - only files go, and directories left empty are pruned
# afterwards, bottom-up.
removed=0
while IFS= read -r -d '' relative; do
    extension="${relative##*.}"
    keep=false
    if [[ "${relative,,}" != *sample* ]]; then
        for candidate in $VIDEO_EXTENSIONS $EXTRA_EXTENSIONS; do
            if [[ "${extension,,}" == "$candidate" ]]; then
                keep=true
                break
            fi
        done
    fi
    if [[ "$keep" != true ]]; then
        rm -f "$INCOMING/$relative" && removed=$((removed + 1))
    fi
done < <(cd "$INCOMING" && find . -type f -printf '%P\0')

find "$INCOMING" -mindepth 1 -depth -type d -empty -delete
echo "[INFO] Allowlist removed $removed file(s) from $RELEASE"

# Nothing to seed without a video file. upPollo would refuse the release anyway
# with `packed release detected`, so letting it through would only produce a
# failure notification and a parked entry under staging/failed - but it must not
# vanish silently either, hence the warning.
video_args=()
for candidate in $VIDEO_EXTENSIONS; do
    video_args+=(-o -iname "*.$candidate")
done
if [[ -z "$(cd "$INCOMING" && find . -type f \( "${video_args[@]:1}" \) -print -quit)" ]]; then
    echo "[WARN] No video file survived the allowlist in $RELEASE, nothing staged"
    notify_warning "$(printf '**%s**\n\n🏷️ Category: %s\n📝 Reason: no video file survived the staging allowlist, so the release was never staged.' \
        "$RELEASE" "$CATEGORY")"
    rm -rf "$INCOMING"
    exit 0
fi

if ! mv "$INCOMING" "$TARGET"; then
    echo "[ERROR] Could not move $INCOMING into $TARGET"
    rm -rf "$INCOMING"
    exit 1
fi

echo "[INFO] Staged $RELEASE under $TARGET"
exit 0
