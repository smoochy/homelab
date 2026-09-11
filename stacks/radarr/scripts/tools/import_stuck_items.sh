#!/usr/bin/env bash
# Import the queue items Radarr downloaded but never imported.
#
# A completed download that Radarr will not import on its own sits in the queue
# as `completed` / `importPending` forever and needs a human to walk it through
# Manual Import. The common cause here is two releases of the same film in the
# queue at once: whichever completes first is imported, and the second is then
# refused as "Not a Custom Format upgrade" against the file its sibling just
# delivered. `supersede_queue.sh` removes that cause at the grab; this is the
# sweep for what is stuck already, and for the other ways an import stalls.
#
# It replaces a hand-placed helper of the same name that sat unversioned in
# appdata since May 2025, with its API key in plain text, Radarr's port wrong,
# a `python3` dependency the container does not have, and its import POSTed to
# `/api/v3/manualimport` - which is `ReprocessItems` and imports nothing. The
# import runs through the `ManualImport` command, which is the endpoint that
# actually moves a file.
#
# Install: Settings > Connect > Custom Script, "On File Import" - a sibling
# finishing is exactly when the blocked one becomes importable. Also runnable by
# hand, and from cron for the stalls no import event follows.
#
# Usage: import_stuck_items.sh [--dry-run]

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in radarr_api.sh.
LOG_TAG=import-stuck
# shellcheck source=./radarr_api.sh
. "$(dirname "$(readlink -f "$0")")/radarr_api.sh"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=true; log "dry run, nothing will be changed"; }

# Radarr tests a custom script with this event and expects a clean exit. Every
# other event is a legitimate trigger: the sweep reads the queue itself and does
# not care which import woke it.
[ "${radarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }

radarr_api_init

# The only rejection this script is allowed to clear, because it is the only one
# that is about the library rather than about the file. Anything else - a sample,
# an unparseable name, an unknown movie - is a real refusal and stays refused.
CLEARABLE_REJECTION='Not a Custom Format upgrade'

# The movie's current file as id and score, or an empty line when it has none.
# Asked of the movie rather than read off the candidate, because a candidate whose
# title Radarr could not match carries neither.
existing_file() {
    api GET "/api/v3/moviefile?movieId=$1" \
        | "${JQ:-jq}" -r 'if type == "array" and length > 0 then "\(.[0].id)\t\(.[0].customFormatScore // 0)" else "" end'
}

import_one() {
    local candidate="$1" title="$2" queue_movie_id="$3"
    local rel path movie_id cand_score rejections existing movie_file_id have

    rel="$("${JQ:-jq}" -r '.relativePath // .name // ""' <<< "$candidate")"
    path="$("${JQ:-jq}" -r '.path // ""' <<< "$candidate")"
    # The queue entry knows which movie was grabbed even when the release name
    # tells Radarr nothing - a German release of an English film has no matching
    # title, and Radarr then logs "No matching movie for titles" on every queue
    # refresh and leaves the import to a human. That is the case this prefers the
    # queue's own id for; the candidate's own match is only the fallback.
    movie_id="$queue_movie_id"
    [ -n "$movie_id" ] && [ "$movie_id" != "0" ] || movie_id="$("${JQ:-jq}" -r '.movie.id // 0' <<< "$candidate")"
    cand_score="$("${JQ:-jq}" -r '.customFormatScore // 0' <<< "$candidate")"
    # Every rejection that is not the clearable one, so an empty result means the
    # file is either clean or blocked only by the library.
    rejections="$("${JQ:-jq}" -r --arg ok "$CLEARABLE_REJECTION" \
        '[.rejections[]? | .reason // "" | select(startswith($ok) | not)] | join("; ")' <<< "$candidate")"

    [ "$movie_id" != "0" ] || { log "  skip, no movie matched: $rel"; return 0; }
    [ -z "$rejections" ] || { log "  skip, rejected: $rejections"; return 0; }

    existing="$(existing_file "$movie_id")"
    if [ -n "$existing" ]; then
        movie_file_id="${existing%%	*}"
        have="${existing##*	}"
        # The guard the old script did not have. It deleted the existing file
        # whenever a candidate was refused as no upgrade, without asking which of
        # the two was better - so running it unattended would replace a good file
        # with a worse one, which is the exact opposite of what the refusal meant.
        if [ "$cand_score" -le "$have" ]; then
            log "  skip, candidate score $cand_score does not beat existing $have: $rel"
            return 0
        fi
        log "  candidate $cand_score beats existing $have, removing movie file $movie_file_id"
        if [ "$DRY_RUN" = true ]; then
            log "  dry run: would DELETE /api/v3/moviefile/$movie_file_id"
        else
            api DELETE "/api/v3/moviefile/$movie_file_id" >/dev/null || {
                log "  WARN could not remove movie file $movie_file_id"
                return 0
            }
        fi
    fi

    local payload
    payload="$("${JQ:-jq}" -c --argjson mid "$movie_id" '{
        name: "ManualImport",
        importMode: "auto",
        files: [{
            path: .path,
            movieId: $mid,
            quality: .quality,
            languages: .languages,
            releaseGroup: .releaseGroup,
            indexerFlags: (.indexerFlags // 0),
            downloadId: (.downloadId // "")
        }]
    }' <<< "$candidate")"

    if [ "$DRY_RUN" = true ]; then
        log "  dry run: would import $rel ($path) into movie $movie_id"
        return 0
    fi

    log "  importing $rel into movie $movie_id"
    api POST "/api/v3/command" -d "$payload" >/dev/null || log "  WARN import command failed for $rel"
    # The command is queued, and a burst of them against the same movie races on
    # the same directory. One at a time is fast enough for a queue sweep.
    sleep 1
    log "  queued (was stuck: $title)"
}

queue="$(api GET "/api/v3/queue?pageSize=200&includeMovie=false")" || { log "queue lookup failed"; exit 1; }

stuck="$(printf '%s' "$queue" | "${JQ:-jq}" -r '
    .records[]?
    | select(.status == "completed" and .trackedDownloadState == "importPending")
    | "\(.title)\t\(.outputPath // "")\t\(.downloadId // "")\t\(.movieId // 0)"
')"

[ -n "$stuck" ] || { log "no stuck imports"; exit 0; }

while IFS=$'\t' read -r title output_path download_id queue_movie_id; do
    [ -n "$title" ] || continue
    log "stuck: $title"
    [ -n "$output_path" ] || { log "  skip, no outputPath"; continue; }

    # filterExistingFiles=false, or Radarr hides exactly the candidate that is
    # blocked by an existing file - which is the case this script exists for.
    candidates="$(api GET "/api/v3/manualimport?folder=$(uri_encode "$output_path")&downloadId=$(uri_encode "$download_id")&filterExistingFiles=false")" || {
        log "  WARN manualimport lookup failed"
        continue
    }

    count="$("${JQ:-jq}" -r 'if type == "array" then length else 0 end' <<< "$candidates")"
    [ "$count" != "0" ] || { log "  no import candidates in $output_path"; continue; }

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        import_one "$candidate" "$title" "$queue_movie_id"
    done <<< "$("${JQ:-jq}" -c '.[]' <<< "$candidates")"
done <<< "$stuck"

log "done"
