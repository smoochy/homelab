#!/usr/bin/env bash
# Import the queue items Sonarr downloaded but never imported.
#
# A completed download that Sonarr will not import on its own sits in the queue
# as `completed` / `importPending` forever and needs a human to walk it through
# Manual Import. Two causes dominate: two releases of the same episode in the
# queue at once, where the second is refused as no Custom Format upgrade against
# the file its sibling just delivered; and a release whose name Sonarr cannot
# match to a series at all, which is what a German release of an English show
# looks like until the indexer proxy learns its title. `supersede_queue.sh`
# removes the first cause at the grab; this is the sweep for what is stuck
# already.
#
# Install: Settings > Connect > Custom Script, "On Import" - a sibling finishing
# is exactly when the blocked one becomes importable - and "On Manual Interaction
# Required", which is the only event a title-match failure raises. Also runnable
# by hand, and from cron for the stalls no event follows.
#
# Usage: import_stuck_items.sh [--dry-run]

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in sonarr_api.sh.
LOG_TAG=import-stuck
# shellcheck source=./sonarr_api.sh
. "$(dirname "$(readlink -f "$0")")/sonarr_api.sh"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=true; log "dry run, nothing will be changed"; }

# Sonarr tests a custom script with this event and expects a clean exit. Every
# other event is a legitimate trigger: the sweep reads the queue itself and does
# not care which import woke it.
[ "${sonarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }

sonarr_api_init

# The only rejection this script is allowed to clear, because it is the only one
# that is about the library rather than about the file. Anything else - a sample,
# an unparseable name, an unknown series - is a real refusal and stays refused.
CLEARABLE_REJECTION='Not a Custom Format upgrade'

# The file currently held for an episode, as id and score, or an empty line when
# the episode has none. Asked of the episode rather than read off the candidate,
# because a candidate whose title Sonarr could not match carries neither.
existing_file() {
    local episode file_id
    episode="$(api GET "/api/v3/episode/$1")" || return 0
    file_id="$("${JQ:-jq}" -r '.episodeFileId // 0' <<< "$episode")"
    [ "$file_id" != "0" ] || return 0
    api GET "/api/v3/episodefile/$file_id" \
        | "${JQ:-jq}" -r '"\(.id)\t\(.customFormatScore // 0)"'
}

import_one() {
    local candidate="$1" title="$2" queue_series_id="$3" queue_episode_id="$4"
    local rel path series_id episode_ids cand_score rejections existing file_id have

    rel="$("${JQ:-jq}" -r '.relativePath // .name // ""' <<< "$candidate")"
    path="$("${JQ:-jq}" -r '.path // ""' <<< "$candidate")"
    cand_score="$("${JQ:-jq}" -r '.customFormatScore // 0' <<< "$candidate")"
    # The queue entry knows which series and episode were grabbed even when the
    # release name tells Sonarr nothing, so it wins over the candidate's own
    # match. The candidate is the fallback, and the only source that can name
    # more than one episode for a multi-episode file.
    series_id="$queue_series_id"
    [ -n "$series_id" ] && [ "$series_id" != "0" ] || series_id="$("${JQ:-jq}" -r '.series.id // 0' <<< "$candidate")"
    episode_ids="$("${JQ:-jq}" -r '[.episodes[]?.id] | join(" ")' <<< "$candidate")"
    [ -n "$episode_ids" ] || episode_ids="$queue_episode_id"
    # Every rejection that is not the clearable one, so an empty result means the
    # file is either clean or blocked only by the library.
    rejections="$("${JQ:-jq}" -r --arg ok "$CLEARABLE_REJECTION" \
        '[.rejections[]? | .reason // "" | select(startswith($ok) | not)] | join("; ")' <<< "$candidate")"

    [ "$series_id" != "0" ] || { log "  skip, no series matched: $rel"; return 0; }
    [ -n "$episode_ids" ] && [ "$episode_ids" != "0" ] || { log "  skip, no episode matched: $rel"; return 0; }
    [ -z "$rejections" ] || { log "  skip, rejected: $rejections"; return 0; }

    # Every episode this file would cover has to be a strict upgrade. One episode
    # already held at a better score is enough to leave the whole file alone -
    # importing it would replace that file too.
    local to_delete="" episode_id
    for episode_id in $episode_ids; do
        existing="$(existing_file "$episode_id")"
        [ -n "$existing" ] || continue
        file_id="${existing%%	*}"
        have="${existing##*	}"
        # The guard the predecessor did not have. It deleted the existing file
        # whenever a candidate was refused as no upgrade, without asking which of
        # the two was better - so running it unattended would replace a good file
        # with a worse one, which is the exact opposite of what the refusal meant.
        if [ "$cand_score" -le "$have" ]; then
            log "  skip, candidate score $cand_score does not beat existing $have on episode $episode_id: $rel"
            return 0
        fi
        to_delete="$to_delete $file_id"
    done

    for file_id in $to_delete; do
        log "  candidate $cand_score beats the existing file, removing episode file $file_id"
        if [ "$DRY_RUN" = true ]; then
            log "  dry run: would DELETE /api/v3/episodefile/$file_id"
        else
            api DELETE "/api/v3/episodefile/$file_id" >/dev/null || {
                log "  WARN could not remove episode file $file_id"
                return 0
            }
        fi
    done

    local payload
    payload="$("${JQ:-jq}" -c --argjson sid "$series_id" --argjson eids "[$(echo "$episode_ids" | tr ' ' ',')]" '{
        name: "ManualImport",
        importMode: "auto",
        files: [{
            path: .path,
            seriesId: $sid,
            episodeIds: $eids,
            quality: .quality,
            languages: .languages,
            releaseGroup: .releaseGroup,
            indexerFlags: (.indexerFlags // 0),
            downloadId: (.downloadId // "")
        }]
    }' <<< "$candidate")"

    if [ "$DRY_RUN" = true ]; then
        log "  dry run: would import $rel ($path) into series $series_id episodes $episode_ids"
        return 0
    fi

    log "  importing $rel into series $series_id episodes $episode_ids"
    api POST "/api/v3/command" -d "$payload" >/dev/null || log "  WARN import command failed for $rel"
    # The command is queued, and a burst of them against the same series races on
    # the same directory. One at a time is fast enough for a queue sweep.
    sleep 1
    log "  queued (was stuck: $title)"
}

queue="$(api GET "/api/v3/queue?pageSize=200&includeSeries=false&includeEpisode=false")" || { log "queue lookup failed"; exit 1; }

stuck="$(printf '%s' "$queue" | "${JQ:-jq}" -r '
    .records[]?
    | select(.status == "completed" and .trackedDownloadState == "importPending")
    | "\(.title)\t\(.outputPath // "")\t\(.downloadId // "")\t\(.seriesId // 0)\t\(.episodeId // 0)"
')"

[ -n "$stuck" ] || { log "no stuck imports"; exit 0; }

while IFS=$'\t' read -r title output_path download_id queue_series_id queue_episode_id; do
    [ -n "$title" ] || continue
    log "stuck: $title"
    [ -n "$output_path" ] || { log "  skip, no outputPath"; continue; }

    # filterExistingFiles=false, or Sonarr hides exactly the candidate that is
    # blocked by an existing file - which is the case this script exists for.
    candidates="$(api GET "/api/v3/manualimport?folder=$(uri_encode "$output_path")&downloadId=$(uri_encode "$download_id")&filterExistingFiles=false")" || {
        log "  WARN manualimport lookup failed"
        continue
    }

    count="$("${JQ:-jq}" -r 'if type == "array" then length else 0 end' <<< "$candidates")"
    [ "$count" != "0" ] || { log "  no import candidates in $output_path"; continue; }

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        import_one "$candidate" "$title" "$queue_series_id" "$queue_episode_id"
    done <<< "$("${JQ:-jq}" -c '.[]' <<< "$candidates")"
done <<< "$stuck"

log "done"
