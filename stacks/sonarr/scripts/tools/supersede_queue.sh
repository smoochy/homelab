#!/usr/bin/env bash
# Sonarr "On Grab" custom script: cancel already-queued releases that cover the
# same episodes as the release just grabbed and score lower than it.
#
# Sonarr behaves like Radarr here: the queue is consulted when a release is
# evaluated, but nothing ever removes an item that is already downloading. A
# better release grabbed while a worse one is still in flight leaves both jobs
# running, both are imported in turn, and the second import wins. The upstream
# answer is a Delay Profile, which costs latency on every grab; this host wants
# grabs immediate, so the loser is cancelled after the fact instead.
#
# The one thing this has to get right that the Radarr version does not: a grab
# is for a set of episodes, and a season pack overlaps a single episode without
# being replaced by it. Only queue items whose episodes are entirely covered by
# the grabbed release are touched.
#
# Install: Settings > Connect > Custom Script, "On Grab" only.

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in sonarr_api.sh.
LOG_TAG=supersede
# shellcheck source=./sonarr_api.sh
. "$(dirname "$(readlink -f "$0")")/sonarr_api.sh"

# Sonarr runs every custom script once with this event when the connection is
# tested, and expects a clean exit.
[ "${sonarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }
[ "${sonarr_eventtype:-}" = "Grab" ] || { log "event ${sonarr_eventtype:-none}, not a grab"; exit 0; }

series_id="${sonarr_series_id:-}"
new_score="${sonarr_release_customformatscore:-}"
# Comma separated, and the reason this script cannot simply compare by series.
episode_ids="${sonarr_release_episodeids:-}"
# Sonarr sets this only once the client has accepted the release, so it can be
# empty here. Matching on it is a courtesy; the score comparison is what actually
# protects the new job from cancelling itself.
new_download_id="${sonarr_download_id:-}"

[ -n "$series_id" ] || { log "no sonarr_series_id"; exit 0; }
[ -n "$new_score" ] || { log "no sonarr_release_customformatscore"; exit 0; }
[ -n "$episode_ids" ] || { log "no sonarr_release_episodeids"; exit 0; }

sonarr_api_init

# queue/details rather than the paged /queue: it takes a seriesId, returns every
# item unpaged, and each record already names the episode it belongs to.
queue="$(api GET "/api/v3/queue/details?seriesId=${series_id}")" || {
    log "queue lookup failed"
    exit 1
}

# Strictly worse, and overlapping. An equal score is left alone: it may be the
# grab that triggered this run before its download id was known, and two releases
# this profile cannot tell apart are not worth cancelling one of.
victims="$(printf '%s' "$queue" | "${JQ:-jq}" -r \
    --argjson new "$new_score" --arg self "$new_download_id" --arg eps "$episode_ids" '
    ($eps | split(",") | map(tonumber)) as $grabbed
    | .[]?
    | select((.customFormatScore // 0) < $new)
    | select(($self == "") or ((.downloadId // "") != $self))
    | ([(.episodeId // empty)] + [.episodes[]?.id] | unique) as $covered
    # Subset, not overlap: a season pack that happens to contain the grabbed
    # episode also contains episodes this grab does not replace, and cancelling
    # it would lose them.
    | select(($covered | length) > 0 and (($covered - $grabbed) | length) == 0)
    | "\(.id)\t\(.customFormatScore // 0)\t\(.title)"
')"

[ -n "$victims" ] || { log "nothing queued below score $new_score for episodes $episode_ids"; exit 0; }

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
