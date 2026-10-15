#!/usr/bin/env bash
# One Sonarr custom script for the download queue, dispatched on the event.
#
# On Grab: cancel already-queued releases that cover the same episodes as the
# release just grabbed and score lower than it. Sonarr consults the queue when a
# release is evaluated, but nothing ever removes an item that is already
# downloading, so a better release grabbed while a worse one is in flight leaves
# both jobs running and the second import wins. The upstream answer is a Delay
# Profile, which costs latency on every grab; this host wants grabs immediate, so
# the loser is cancelled after the fact instead. A grab is for a set of episodes
# and a season pack overlaps a single episode without being replaced by it, so
# only queue items whose episodes are entirely covered by the grabbed release are
# touched.
#
# Any other event (On Import, On Manual Interaction Required): import the queue
# items Sonarr downloaded but never imported. A completed download that Sonarr
# will not import on its own sits in the queue as `completed` / `importPending`
# or `completed` / `importBlocked` forever - the latter is what a grab matched to
# the series by indexer id becomes, and Sonarr refuses it with "release was
# matched to series by ID" - and needs a human to walk it through Manual Import.
# Two causes dominate: two releases of the same episode in the queue at once,
# where the second is refused as no Custom Format upgrade against the file its
# sibling just delivered; and a release whose name Sonarr cannot match to a
# series at all, which is what a German release of an English show looks like
# until the indexer proxy learns its title. The grab half removes the first cause
# at the grab; the import half is the sweep for what is stuck already.
#
# Install: Settings > Connect > Custom Script, "On Grab", "On Import" - a sibling
# finishing is exactly when the blocked one becomes importable - and "On Manual
# Interaction Required", which is the only event a title-match failure raises.
# The events are the whole trigger set; no host cron is involved. Also runnable by
# hand: with no Sonarr event in the environment it runs the import sweep.
#
# Usage: queue_housekeeping.sh [--dry-run]   (--dry-run applies to the import sweep)
#
# Keep this file committed 100755. deliver.sh installs a source at the row mode only
# when it is executable, and skips a file whose content already matches the host copy,
# so a mode fixed after the first delivery is not picked up until the content changes.

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in sonarr_api.sh.
LOG_TAG=housekeeping
# shellcheck source=./sonarr_api.sh
. "$(dirname "$(readlink -f "$0")")/sonarr_api.sh"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=true; log "dry run, nothing will be changed"; }

# Sonarr tests a custom script with this event and expects a clean exit.
[ "${sonarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }

# ---- On Grab: cancel superseded queue items ---------------------------------

supersede() {
    local series_id new_score episode_ids new_download_id queue victims id score title
    series_id="${sonarr_series_id:-}"
    new_score="${sonarr_release_customformatscore:-}"
    # Comma separated, and the reason this cannot simply compare by series.
    episode_ids="${sonarr_release_episodeids:-}"
    # Sonarr sets this only once the client has accepted the release, so it can be
    # empty here. Matching on it is a courtesy; the score comparison is what
    # actually protects the new job from cancelling itself.
    new_download_id="${sonarr_download_id:-}"

    [ -n "$series_id" ] || { log "no sonarr_series_id"; return 0; }
    [ -n "$new_score" ] || { log "no sonarr_release_customformatscore"; return 0; }
    [ -n "$episode_ids" ] || { log "no sonarr_release_episodeids"; return 0; }

    # queue/details rather than the paged /queue: it takes a seriesId, returns
    # every item unpaged, and each record already names the episode it belongs to.
    queue="$(api GET "/api/v3/queue/details?seriesId=${series_id}")" || {
        log "queue lookup failed"
        return 1
    }

    # Strictly worse, and overlapping. An equal score is left alone: it may be the
    # grab that triggered this run before its download id was known, and two
    # releases this profile cannot tell apart are not worth cancelling one of.
    victims="$(printf '%s' "$queue" | "${JQ:-jq}" -r \
        --argjson new "$new_score" --arg self "$new_download_id" --arg eps "$episode_ids" '
        ($eps | split(",") | map(tonumber)) as $grabbed
        | .[]?
        | select((.customFormatScore // 0) < $new)
        | select(($self == "") or ((.downloadId // "") != $self))
        | ([(.episodeId // empty)] + [.episodes[]?.id] | unique) as $covered
        # Subset, not overlap: a season pack that happens to contain the grabbed
        # episode also contains episodes this grab does not replace, and
        # cancelling it would lose them.
        | select(($covered | length) > 0 and (($covered - $grabbed) | length) == 0)
        | "\(.id)\t\(.customFormatScore // 0)\t\(.title)"
    ')"

    [ -n "$victims" ] || { log "nothing queued below score $new_score for episodes $episode_ids"; return 0; }

    while IFS=$'\t' read -r id score title; do
        [ -n "$id" ] || continue
        log "removing queue id=$id score=$score < $new_score : $title"
        # skipRedownload, or Sonarr immediately searches a replacement for the very
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

# The series id and episode ids Sonarr recorded when it grabbed this download, as
# "seriesId<tab>ep ep ...", or "0" alone. The grab rows are the one source that is
# right even when nothing about the release name is: Sonarr wrote them from the
# decision it made at grab time, not from the title. A multi-episode grab writes
# one row per episode, so the ids are collected across all of them.
ids_from_history() {
    [ -n "$1" ] || { printf '0'; return 0; }
    api GET "/api/v3/history?pageSize=100&eventType=1&downloadId=$(uri_encode "$1")" \
        | "${JQ:-jq}" -r '[.records[]?] | if length == 0 then "0"
            else "\(.[0].seriesId // 0)\t\([.[].episodeId // empty] | unique | join(" "))" end'
}

import_one() {
    local candidate="$1" title="$2" queue_series_id="$3" queue_episode_id="$4" download_id="$5"
    local history_ids=""
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
    # An item Sonarr matched to nothing carries no ids in either place, so the
    # grab's own history rows are the last fallback - and the only one left for
    # exactly the release this script is meant to rescue.
    if [ "$series_id" = "0" ] || [ -z "$episode_ids" ] || [ "$episode_ids" = "0" ]; then
        history_ids="$(ids_from_history "$download_id")"
        [ "$series_id" != "0" ] || series_id="${history_ids%%	*}"
        [ -n "$episode_ids" ] && [ "$episode_ids" != "0" ] || episode_ids="${history_ids#*	}"
        [ "$episode_ids" != "$history_ids" ] || episode_ids=""
    fi
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

import_sweep() {
    local queue stuck title output_path download_id queue_series_id queue_episode_id candidates count candidate

    # includeUnknownSeriesItems, or the queue hides every item Sonarr could not match
    # to a series - which is precisely the stuck state this script exists for. Without
    # it a release whose name Sonarr cannot parse is invisible here and the sweep
    # reports an empty queue while the item sits in Activity waiting for a human.
    queue="$(api GET "/api/v3/queue?pageSize=200&includeSeries=false&includeEpisode=false&includeUnknownSeriesItems=true")" || { log "queue lookup failed"; return 1; }

    stuck="$(printf '%s' "$queue" | "${JQ:-jq}" -r '
        .records[]?
        | select(.status == "completed" and (.trackedDownloadState | IN("importPending", "importBlocked")))
        | "\(.title)\t\(.outputPath // "")\t\(.downloadId // "")\t\(.seriesId // 0)\t\(.episodeId // 0)"
    ')"

    # The counts, because "no stuck imports" on its own cannot be told apart from a
    # filter that threw away the item the run was woken for.
    [ -n "$stuck" ] || {
        log "no stuck imports ($("${JQ:-jq}" -r '.records | length' <<< "$queue") queue items, none completed+importPending/importBlocked)"
        return 0
    }

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
            import_one "$candidate" "$title" "$queue_series_id" "$queue_episode_id" "$download_id"
        done <<< "$("${JQ:-jq}" -c '.[]' <<< "$candidates")"
    done <<< "$stuck"

    log "done"
}

# ---- Dispatch ----------------------------------------------------------------

sonarr_api_init

# An empty event is a hand run. Anything else Sonarr might send is not ours.
case "${sonarr_eventtype:-}" in
    Grab) supersede ;;
    Download | ManualInteractionRequired | "") import_sweep ;;
    *) log "event ${sonarr_eventtype}, nothing to do" ;;
esac
