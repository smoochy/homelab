#!/usr/bin/env bash
# Runs import_stuck_items.sh against a fake curl serving a fixture queue, manual
# import candidates and episode files. The cases that matter: an existing file is
# only ever deleted for a candidate that actually scores higher, and a release
# Sonarr could not match to a series still imports because the queue entry knows
# what it belongs to.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../import_stuck_items.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/config.xml" <<'XML'
<Config>
  <Port>8989</Port>
  <ApiKey>testkey</ApiKey>
  <UrlBase></UrlBase>
</Config>
XML

cat > "$work/queue.json" <<'JSON'
{"records":[
 {"id":11,"title":"Show.S05E01.GERMAN.DL.2160p-GRP","seriesId":42,"episodeId":501,"status":"completed","trackedDownloadState":"importPending","outputPath":"/data/usenet/tv/Show.S05E01-GRP","downloadId":"AAA"},
 {"id":12,"title":"Show.S05E02.Still.Downloading-GRP","seriesId":42,"episodeId":502,"status":"downloading","trackedDownloadState":"downloading","outputPath":"/data/usenet/tv/Show.S05E02-GRP","downloadId":"BBB"}
]}
JSON

# Written per case; the fake curl serves whichever set the case installed.
write_candidate() {
    cat > "$work/manualimport.json" <<JSON
[{"path":"/data/usenet/tv/Show.S05E01-GRP/file.mkv",
  "relativePath":"file.mkv",
  "series":{"id":42},
  "episodes":[{"id":501}],
  "customFormatScore":$1,
  "quality":{"quality":{"id":18,"name":"WEBDL-2160p"}},
  "languages":[{"id":4,"name":"German"}],
  "releaseGroup":"GRP",
  "indexerFlags":0,
  "downloadId":"AAA",
  "rejections":$2}]
JSON
}

# A release Sonarr cannot title-match: no series and no episodes on the candidate
# at all. This is the German-release case the sweep exists for, and the queue
# entry is the only thing that knows what it belongs to.
write_unmatched_candidate() {
    cat > "$work/manualimport.json" <<'JSON'
[{"path":"/data/usenet/tv/Show.S05E01-GRP/file.mkv",
  "relativePath":"file.mkv",
  "series":null,
  "episodes":[],
  "customFormatScore":0,
  "quality":{"quality":{"id":9,"name":"WEBDL-1080p"}},
  "languages":[{"id":4,"name":"German"}],
  "releaseGroup":"GRP",
  "indexerFlags":0,
  "downloadId":"AAA",
  "rejections":[]}]
JSON
}

# The episode's current file, or none at all.
write_episodefile() {
    if [ "$1" = none ]; then
        printf '{"id":501,"episodeFileId":0}\n' > "$work/episode.json"
        printf '{}\n' > "$work/episodefile.json"
    else
        printf '{"id":501,"episodeFileId":%s}\n' "$1" > "$work/episode.json"
        printf '{"id":%s,"customFormatScore":%s}\n' "$1" "$2" > "$work/episodefile.json"
    fi
}

cat > "$work/curl" <<'SH'
#!/usr/bin/env bash
args=("$@")
method=GET
body=
for ((i = 0; i < ${#args[@]}; i++)); do
    [ "${args[$i]}" = "-X" ] && method="${args[$((i + 1))]}"
    [ "${args[$i]}" = "-d" ] && body="${args[$((i + 1))]}"
done
url="${args[-1]}"
echo "$method $url" >> "$WORK/requests.log"
[ -n "$body" ] && printf '%s\n' "$body" >> "$WORK/bodies.log"
case "$method:$url" in
    GET:*/api/v3/queue*)        cat "$WORK/queue.json" ;;
    GET:*/api/v3/manualimport*) cat "$WORK/manualimport.json" ;;
    GET:*/api/v3/episodefile/*) cat "$WORK/episodefile.json" ;;
    GET:*/api/v3/episode/*)     cat "$WORK/episode.json" ;;
esac
exit 0
SH
chmod +x "$work/curl"

run() {
    : > "$work/requests.log"
    : > "$work/bodies.log"
    env WORK="$work" CURL="$work/curl" SONARR_CONFIG="$work/config.xml" \
        bash "$script" "$@" > "$work/out.log" 2>&1
}

fail() {
    echo "FAIL: $1"
    echo "--- output ---"; cat "$work/out.log"
    echo "--- requests ---"; cat "$work/requests.log"
    exit 1
}
count() { grep -c "$1" "$work/requests.log" || true; }

# The episode has no file: the candidate imports with nothing deleted.
write_candidate 22300 '[]'
write_episodefile none
run
[ "$(count 'DELETE .*episodefile')" = "0" ] || fail "nothing may be deleted when the episode has no file"
grep -q '"name":"ManualImport"' "$work/bodies.log" || fail "no ManualImport command issued"
grep -q '"seriesId":42' "$work/bodies.log" || fail "import payload lost the seriesId"
grep -q '"episodeIds":\[501\]' "$work/bodies.log" || fail "import payload lost the episodeIds"

# The candidate beats the existing file: the file goes, the import follows.
write_candidate 22800 '[{"reason":"Not a Custom Format upgrade for existing episode file(s)"}]'
write_episodefile 900 22300
run
[ "$(count 'DELETE .*episodefile/900')" = "1" ] || fail "a better candidate must replace the existing file"
grep -q '"name":"ManualImport"' "$work/bodies.log" || fail "import must follow the delete"

# The candidate is worse: this is the predecessor's bug, and it must not happen.
write_candidate 21800 '[{"reason":"Not a Custom Format upgrade for existing episode file(s)"}]'
write_episodefile 900 22800
run
[ "$(count '^DELETE')" = "0" ] || fail "a worse candidate must never delete the existing file"
[ "$(count '^POST')" = "0" ] || fail "a worse candidate must never be imported"

# An equal score is not an upgrade either.
write_candidate 22800 '[{"reason":"Not a Custom Format upgrade for existing episode file(s)"}]'
write_episodefile 900 22800
run
[ "$(count '^DELETE')" = "0" ] || fail "an equal candidate must not replace the existing file"

# A rejection that is not about the library is a real refusal and stays refused.
write_candidate 22800 '[{"reason":"Sample"}]'
write_episodefile none
run
[ "$(count '^POST')" = "0" ] || fail "a sample must not be imported"

# Dry run touches nothing, even in the case that would otherwise act.
write_candidate 22800 '[{"reason":"Not a Custom Format upgrade for existing episode file(s)"}]'
write_episodefile 900 22300
run --dry-run
[ "$(count '^DELETE')" = "0" ] || fail "dry run deleted something"
[ "$(count '^POST')" = "0" ] || fail "dry run imported something"

# Only the stuck item is looked at; the still-downloading one is not.
write_candidate 22300 '[]'
write_episodefile none
run
[ "$(count 'Still.Downloading')" = "0" ] || fail "a downloading item must not be swept"
grep -q 'filterExistingFiles=false' "$work/requests.log" || fail "candidates must not be filtered by existing files"

# The candidate Sonarr could not match still imports, because the queue entry
# names the series and the episode. This is what needed a human before.
write_unmatched_candidate
write_episodefile none
run
grep -q '"seriesId":42' "$work/bodies.log" || fail "an unmatched candidate must import against the queue's seriesId"
grep -q '"episodeIds":\[501\]' "$work/bodies.log" || fail "an unmatched candidate must import against the queue's episodeId"

# ... but the score guard still applies to it: the library file wins.
write_unmatched_candidate
write_episodefile 900 22800
run
[ "$(count '^DELETE')" = "0" ] || fail "an unmatched candidate must not replace a better existing file"
[ "$(count '^POST')" = "0" ] || fail "an unmatched candidate must not be imported over a better file"

# Sonarr's connection test exits clean without reading the queue.
: > "$work/requests.log"
env WORK="$work" CURL="$work/curl" SONARR_CONFIG="$work/config.xml" sonarr_eventtype=Test \
    bash "$script" > "$work/out.log" 2>&1
[ "$(count 'api/v3')" = "0" ] || fail "the test event must not call the API"

echo "test_import_stuck_items: all checks passed"
