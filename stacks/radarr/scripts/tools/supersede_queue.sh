#!/usr/bin/env bash
# Radarr "On Grab" custom script: cancel already-queued releases of the same
# movie that score lower than the release just grabbed.
#
# Radarr does not do this itself, in any version. `QueueSpecification.cs` is the
# only place a candidate is compared against what is already queued, and every
# branch in it ends in `Reject` or `Accept` - there is no path that removes the
# existing item. So a better release grabbed while a worse one is still
# downloading leaves both jobs running to completion, both are imported in turn,
# and the second import wins. Measured on 2026-08-28: two releases of the same
# film grabbed eleven minutes apart, scores 22300 and 22800, both downloaded in
# full.
#
# The sanctioned fix upstream is a Delay Profile, which waits out a window before
# grabbing anything so only the best release of that window is taken. That trades
# the duplicate for latency on every single grab, which is not the trade this
# host wants. Cancelling the loser after the fact keeps grabs immediate.
#
# Install: Settings > Connect > Custom Script, "On Grab" only.

set -euo pipefail

# shellcheck disable=SC2034  # consumed by log() in radarr_api.sh.
LOG_TAG=supersede
# shellcheck source=./radarr_api.sh
. "$(dirname "$(readlink -f "$0")")/radarr_api.sh"

# Radarr runs every custom script once with this event when the connection is
# tested, and expects a clean exit.
[ "${radarr_eventtype:-}" = "Test" ] && { log "test event"; exit 0; }
[ "${radarr_eventtype:-}" = "Grab" ] || { log "event ${radarr_eventtype:-none}, not a grab"; exit 0; }

movie_id="${radarr_movie_id:-}"
new_score="${radarr_release_customformatscore:-}"
# Radarr sets this only once the client has accepted the release, so it can be
# empty here. Matching on it is a courtesy; the score comparison is what actually
# protects the new job from cancelling itself.
new_download_id="${radarr_download_id:-}"

[ -n "$movie_id" ] || { log "no radarr_movie_id"; exit 0; }
[ -n "$new_score" ] || { log "no radarr_release_customformatscore"; exit 0; }

radarr_api_init

queue="$(api GET "/api/v3/queue?pageSize=200&movieIds=${movie_id}&includeMovie=false")" || {
    log "queue lookup failed"
    exit 1
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

[ -n "$victims" ] || { log "nothing queued below score $new_score for movie $movie_id"; exit 0; }

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
