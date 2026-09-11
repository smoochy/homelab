#!/usr/bin/env bash
# Runs supersede_queue.sh against a fake curl that serves a fixture queue and
# records every request, so the deletions it would issue are asserted without a
# Sonarr anywhere near it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../supersede_queue.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/config.xml" <<'XML'
<Config>
  <Port>8989</Port>
  <ApiKey>testkey</ApiKey>
  <UrlBase></UrlBase>
</Config>
XML

# id 14 is a season pack: it covers episode 501 like the others, plus 502, which
# the single-episode grab does not replace.
cat > "$work/queue.json" <<'JSON'
[
 {"id":11,"downloadId":"AAA","episodeId":501,"customFormatScore":22300,"title":"Show.S05E01.GERMAN.DL.1080p.WEB.h264-GRP"},
 {"id":12,"downloadId":"BBB","episodeId":501,"customFormatScore":22800,"title":"Show.S05E01.GERMAN.DL.2160p.WEB.h265-GRP"},
 {"id":13,"downloadId":"CCC","episodeId":501,"customFormatScore":21800,"title":"Show.S05E01.GERMAN.720p.WEB.h264-GRP"},
 {"id":14,"downloadId":"DDD","customFormatScore":21000,"episodes":[{"id":501},{"id":502}],"title":"Show.S05.GERMAN.DL.1080p.WEB.h264-GRP"}
]
JSON

cat > "$work/curl" <<'SH'
#!/usr/bin/env bash
args=("$@")
method=GET
for ((i = 0; i < ${#args[@]}; i++)); do
    [ "${args[$i]}" = "-X" ] && method="${args[$((i + 1))]}"
done
echo "$method ${args[-1]}" >> "$WORK/requests.log"
[ "$method" = "GET" ] && cat "$WORK/queue.json"
exit 0
SH
chmod +x "$work/curl"

run() {
    : > "$work/requests.log"
    env WORK="$work" CURL="$work/curl" SONARR_CONFIG="$work/config.xml" "$@" \
        bash "$script" > "$work/out.log" 2>&1
}

fail() {
    echo "FAIL: $1"
    echo "--- output ---"; cat "$work/out.log"
    echo "--- requests ---"; cat "$work/requests.log"
    exit 1
}
deletes() { grep -c '^DELETE' "$work/requests.log" || true; }
deleted_ids() { grep '^DELETE' "$work/requests.log" | grep -o 'queue/[0-9]*' | cut -d/ -f2 | sort -n | tr '\n' ' '; }

# The best release of the episode is grabbed: both worse single-episode items go,
# the equal-scoring self stays, and the season pack survives because it also
# carries an episode this grab does not replace.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501 \
    sonarr_release_customformatscore=22800 sonarr_download_id=BBB
[ "$(deleted_ids)" = "11 13 " ] || fail "expected ids 11 13, got '$(deleted_ids)'"

# The whole season is grabbed at a better score: now the pack is fully covered
# and goes too.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501,502 \
    sonarr_release_customformatscore=22800 sonarr_download_id=BBB
[ "$(deleted_ids)" = "11 13 14 " ] || fail "expected ids 11 13 14, got '$(deleted_ids)'"

# The worst release is grabbed: nothing above it is touched.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501 \
    sonarr_release_customformatscore=21800 sonarr_download_id=CCC
[ "$(deletes)" = "0" ] || fail "lowest grab must delete nothing, got $(deletes)"

# An episode nothing in the queue belongs to: no collateral damage.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=999 \
    sonarr_release_customformatscore=22800 sonarr_download_id=BBB
[ "$(deletes)" = "0" ] || fail "an unrelated episode must delete nothing"

# Sonarr has not assigned a download id yet: the score alone still protects the
# new grab, and the equal-scoring queue entry survives.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501 \
    sonarr_release_customformatscore=22800 sonarr_download_id=
[ "$(deleted_ids)" = "11 13 " ] || fail "empty downloadId: expected 11 13, got '$(deleted_ids)'"

# The removal must not blocklist the release or trigger a replacement search.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501 \
    sonarr_release_customformatscore=22800 sonarr_download_id=BBB
for flag in skipRedownload=true blocklist=false removeFromClient=true; do
    grep -q "$flag" "$work/requests.log" || fail "$flag missing from the delete"
done

# The queue is read for one series, not for the whole library.
grep -q 'seriesId=42' "$work/requests.log" || fail "queue not filtered by seriesId"

# Any event other than a grab is a no-op, Sonarr's connection test included.
for ev in Test Download Rename SeriesDelete; do
    run sonarr_eventtype="$ev" sonarr_series_id=42 sonarr_release_episodeids=501 \
        sonarr_release_customformatscore=22800
    [ "$(deletes)" = "0" ] || fail "$ev must be a no-op"
done

# A run without the score env var must do nothing rather than treat it as zero.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_episodeids=501
[ "$(deletes)" = "0" ] || fail "missing score must be a no-op"

# A run without the episode ids must do nothing rather than hit the whole series.
run sonarr_eventtype=Grab sonarr_series_id=42 sonarr_release_customformatscore=22800
[ "$(deletes)" = "0" ] || fail "missing episode ids must be a no-op"

echo "test_supersede_queue: all checks passed"
