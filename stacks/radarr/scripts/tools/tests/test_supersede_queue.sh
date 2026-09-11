#!/usr/bin/env bash
# Runs supersede_queue.sh against a fake curl that serves a fixture queue and
# records every request, so the deletions it would issue are asserted without a
# Radarr anywhere near it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../supersede_queue.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/config.xml" <<'XML'
<Config>
  <Port>7878</Port>
  <ApiKey>testkey</ApiKey>
  <UrlBase></UrlBase>
</Config>
XML

cat > "$work/queue.json" <<'JSON'
{"records":[
 {"id":11,"downloadId":"AAA","customFormatScore":22300,"title":"Der.Kinderfluesterer.2026.GERMAN.DL.HDR.2160p.WEB.h265-SAUERKRAUT"},
 {"id":12,"downloadId":"BBB","customFormatScore":22800,"title":"Der.Kinderfluesterer.2026.GERMAN.DL.DV.2160p.WEB.h265-SAUERKRAUT"},
 {"id":13,"downloadId":"CCC","customFormatScore":21800,"title":"Der.Kinderfluesterer.2026.GERMAN.DL.2160p.WEB.h265-SAUERKRAUT"}
]}
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
    env WORK="$work" CURL="$work/curl" RADARR_CONFIG="$work/config.xml" "$@" \
        bash "$script" > "$work/out.log" 2>&1
}

fail() {
    echo "FAIL: $1"
    echo "--- output ---"; cat "$work/out.log"
    echo "--- requests ---"; cat "$work/requests.log"
    exit 1
}
deletes() { grep -c '^DELETE' "$work/requests.log" || true; }
deleted_ids() { grep -o 'queue/[0-9]*' "$work/requests.log" | cut -d/ -f2 | sort -n | tr '\n' ' '; }

# The best release is grabbed: both worse items go, the equal-scoring self stays.
run radarr_eventtype=Grab radarr_movie_id=1701 radarr_release_customformatscore=22800 radarr_download_id=BBB
[ "$(deleted_ids)" = "11 13 " ] || fail "expected ids 11 13, got '$(deleted_ids)'"

# The worst release is grabbed: nothing above it is touched.
run radarr_eventtype=Grab radarr_movie_id=1701 radarr_release_customformatscore=21800 radarr_download_id=CCC
[ "$(deletes)" = "0" ] || fail "lowest grab must delete nothing, got $(deletes)"

# Radarr has not assigned a download id yet: the score alone still protects the
# new grab, and the equal-scoring queue entry survives.
run radarr_eventtype=Grab radarr_movie_id=1701 radarr_release_customformatscore=22800 radarr_download_id=
[ "$(deleted_ids)" = "11 13 " ] || fail "empty downloadId: expected 11 13, got '$(deleted_ids)'"

# The removal must not blocklist the release or trigger a replacement search.
run radarr_eventtype=Grab radarr_movie_id=1701 radarr_release_customformatscore=22800 radarr_download_id=BBB
for flag in skipRedownload=true blocklist=false removeFromClient=true; do
    grep -q "$flag" "$work/requests.log" || fail "$flag missing from the delete"
done

# The queue is read for one movie, not for the whole library.
grep -q 'movieIds=1701' "$work/requests.log" || fail "queue not filtered by movieIds"

# Any event other than a grab is a no-op, Radarr's connection test included.
for ev in Test Download Rename MovieDelete; do
    run radarr_eventtype="$ev" radarr_movie_id=1701 radarr_release_customformatscore=22800
    [ "$(deletes)" = "0" ] || fail "$ev must be a no-op"
done

# A run without the score env var must do nothing rather than treat it as zero.
run radarr_eventtype=Grab radarr_movie_id=1701
[ "$(deletes)" = "0" ] || fail "missing score must be a no-op"

echo "test_supersede_queue: all checks passed"
