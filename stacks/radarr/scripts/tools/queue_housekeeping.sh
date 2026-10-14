#!/usr/bin/env bash
# One Radarr custom script for the download queue, dispatched on the event.
#
# On Grab: cancel already-queued releases of the same movie that score lower than
# the release just grabbed. Radarr does not do this itself, in any version.
# `QueueSpecification.cs` is the only place a candidate is compared against what
# is already queued, and every branch in it ends in `Reject` or `Accept` - there
# is no path that removes the existing item. So a better release grabbed while a
# worse one is still downloading leaves both jobs running to completion, both are
# imported in turn, and the second import wins. Measured on 2026-08-28: two
# releases of the same film grabbed eleven minutes apart, scores 22300 and 22800,
# both downloaded in full. The sanctioned fix upstream is a Delay Profile, which
# trades the duplicate for latency on every single grab, which is not the trade
# this host wants. Cancelling the loser after the fact keeps grabs immediate.
#
# On File Import and On Manual Interaction Required: import the queue items
# Radarr downloaded but never imported. A completed download that Radarr will not
# import on its own sits in the queue as `completed` / `importPending` or
# `completed` / `importBlocked` forever - the latter is what a grab matched to the
# movie by indexer id becomes, and Radarr refuses it with "release was matched to
# movie by ID" - and needs a human to walk it through Manual Import. The common
# cause here is two releases of the same film in the queue at once: whichever
# completes first is imported, and the second is then refused as "Not a Custom
# Format upgrade" against the file its sibling just delivered. The grab half
# removes that cause; the import half is the sweep for what is stuck already, and
# for the other ways an import stalls. The import runs through the `ManualImport`
# command, which is the endpoint that actually moves a file.
#
# Install: Settings > Connect > Custom Script, "On Grab", "On File Import" - a
# sibling finishing is exactly when the blocked one becomes importable - and "On
# Manual Interaction Required", which is the only event a title-match failure
# raises. The events are the whole trigger set; no host cron is involved. Also
# runnable by hand: with no Radarr event in the environment it runs the import
# sweep.
#
# Usage: queue_housekeeping.sh [--dry-run]   (--dry-run applies to the import sweep)
#
# Keep this file committed 100755. deliver.sh installs a source at the row mode only
# when it is executable, and skips a file whose content already matches the host copy,
# so a mode fixed after the first delivery is not picked up until the content changes.

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in radarr_api.sh.
LOG_TAG=housekeeping
# shellcheck source=./radarr_api.sh
. "$(dirname "$(readlink -f "$0")")/radarr_api.sh"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=true; log "dry run, nothing will be changed"; }

# Radarr tests a custom script with this event and expects a clean exit.
[ "${radarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }

# ---- On Grab: cancel superseded queue items ---------------------------------

supersede() {
    local movie_id new_score new_download_id queue victims id score title
    movie_id="${radarr_movie_id:-}"
    new_score="${radarr_release_customformatscore:-}"
    # Radarr sets this only once the client has accepted the release, so it can be
    # empty here. Matching on it is a courtesy; the score comparison is what
    # actually protects the new job from cancelling itself.
    new_download_id="${radarr_download_id:-}"

    [ -n "$movie_id" ] || { log "no radarr_movie_id"; return 0; }
    [ -n "$new_score" ] || { log "no radarr_release_customformatscore"; return 0; }

    queue="$(api GET "/api/v3/queue?pageSize=200&movieIds=${movie_id}&includeMovie=false")" || {
        log "queue lookup failed"
        return 1
    }

    # Strictly worse only. An equal score is left alone: it may be the grab that
    # triggered this run before its download id was known, and two releases this
    # profile cannot tell apart are not worth cancelling one of.
    victims="$(printf '%s' "$queue" | "${JQ:-jq}" -r --argjson new "$new_score" --arg self "$new_download_id" '
        .records[]
        | select((.customFormatScore // 0) < $new)
        | select(($self == "") or ((.downloadId // "") != $self))
        | "\(.id)\t\(.customFormatScore // 0)\t\(.title)"
    ')"

    [ -n "$victims" ] || { log "nothing queued below score $new_score for movie $movie_id"; return 0; }

    while IFS=$'\t' read -r id score title; do
        [ -n "$id" ] || continue
        log "removing queue id=$id score=$score < $new_score : $title"
        # skipRedownload, or Radarr immediately searches a replacement for the very
        # release just superseded and the pair comes straight back. blocklist stays
        # off: the release did nothing wrong, it only lost.
        api DELETE "/api/v3/queue/${id}?removeFromClient=true&blocklist=false&skipRedownload=true" >/dev/null \
            || log "WARN could not remove queue id=$id"
    done <<< "$victims"

    log "done"
}

# ---- Import sweep ------------------------------------------------------------


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

# The movie id Radarr recorded when it grabbed this download, or 0. The grab row
# is the one source that is right even when nothing about the release name is:
# Radarr wrote it from the decision it made at grab time, not from the title.
movie_id_from_history() {
    [ -n "$1" ] || { printf '0'; return 0; }
    api GET "/api/v3/history?pageSize=50&eventType=1&downloadId=$(uri_encode "$1")" \
        | "${JQ:-jq}" -r '[.records[]?.movieId // empty] | first // 0'
}

import_one() {
    local candidate="$1" title="$2" queue_movie_id="$3" download_id="$4"
    local rel path movie_id cand_score rejections existing movie_file_id have

    rel="$("${JQ:-jq}" -r '.relativePath // .name // ""' <<< "$candidate")"
    path="$("${JQ:-jq}" -r '.path // ""' <<< "$candidate")"
    # The queue entry knows which movie was grabbed even when the release name
    # tells Radarr nothing - a German release of an English film has no matching
    # title, and Radarr then logs "No matching movie for titles" on every queue
    # refresh and leaves the import to a human. That is the case this prefers the
    # queue's own id for; the candidate's own match is only the fallback.
    # An item Radarr matched to no movie at all carries no id in either place, so
    # the grab's own history row is the last fallback - and the only one left for
    # exactly the release this script is meant to rescue.
    movie_id="$queue_movie_id"
    [ -n "$movie_id" ] && [ "$movie_id" != "0" ] || movie_id="$("${JQ:-jq}" -r '.movie.id // 0' <<< "$candidate")"
    [ "$movie_id" != "0" ] || movie_id="$(movie_id_from_history "$download_id")"
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

import_sweep() {
    local queue stuck title output_path download_id queue_movie_id candidates count candidate

    # includeUnknownMovieItems, or the queue hides every item Radarr could not match
    # to a movie - which is precisely the stuck state this script exists for. Without
    # it a German release of an English film is invisible here and the sweep reports
    # an empty queue while the item sits in Activity waiting for a human.
    queue="$(api GET "/api/v3/queue?pageSize=200&includeMovie=false&includeUnknownMovieItems=true")" || { log "queue lookup failed"; return 1; }

    stuck="$(printf '%s' "$queue" | "${JQ:-jq}" -r '
        .records[]?
        | select(.status == "completed" and (.trackedDownloadState | IN("importPending", "importBlocked")))
        | "\(.title)\t\(.outputPath // "")\t\(.downloadId // "")\t\(.movieId // 0)"
    ')"

    # The counts, because "no stuck imports" on its own cannot be told apart from a
    # filter that threw away the item the run was woken for.
    [ -n "$stuck" ] || {
        log "no stuck imports ($("${JQ:-jq}" -r '.records | length' <<< "$queue") queue items, none completed+importPending/importBlocked)"
        return 0
    }

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
            import_one "$candidate" "$title" "$queue_movie_id" "$download_id"
        done <<< "$("${JQ:-jq}" -c '.[]' <<< "$candidates")"
    done <<< "$stuck"

    log "done"
}

# ---- Dispatch ----------------------------------------------------------------

radarr_api_init

# An empty event is a hand run. Anything else Radarr might send is not ours.
case "${radarr_eventtype:-}" in
    Grab) supersede ;;
    Download | ManualInteractionRequired | "") import_sweep ;;
    *) log "event ${radarr_eventtype}, nothing to do" ;;
esac
