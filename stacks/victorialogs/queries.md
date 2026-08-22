# Saved LogsQL queries

The store has no server-side saved queries, so these live here and as bookmarks in Homepage. Paste them into VMUI at `https://${TRAEFIK_EXTERNAL_URL}/select/vmui/`.

Two things to know before reading any of them:

- `app_name` is `<compose project>.<container name>`, built from the syslog driver's tag (#972). The stack is in the name because the driver emits no RFC5424 structured data.
- Ingest is lossy UDP by design. A missing line means the datagram never arrived, not that the event never happened - so a query returning nothing is weak evidence, and an alert that never fired is not proof that nothing broke.

## The level pipeline

Everything below is built on one block that puts a canonical `lvl` field on a line, whatever convention the container writes in (#980). Paste it after your time and app filters, then add whichever tail you need.

```logsql
| extract_regexp `(?i)^(?:.{0,64}?(?:\x1b\[[0-9;]*m|[^a-zA-Z]))?(?P<lvl_w>trace|debug|dbg|notice|info|inf|warning|warn|wrn|error|err|fatal|ftl|critical|crit|panic)(?:\x1b\[[0-9;]*m|[^a-zA-Z]|$)` from _msg
| extract_regexp `^.{0,64}?"s":"(?P<lvl_m>[FEWID][0-9]?)"` from _msg
| extract_regexp `^.{0,64}?"level":(?P<lvl_p>[1-6]0)[,}]` from _msg
| format "<lvl_m>" as lvl
| format if (lvl:"") "<lvl_p>" as lvl
| format if (lvl:"") "<lvl_w>" as lvl
| replace_regexp ("(?i)^(err|error|E|50)$", "error") at lvl
| replace_regexp ("(?i)^(wrn|warn|warning|W|40)$", "warn") at lvl
| replace_regexp ("(?i)^(inf|info|I|30)$", "info") at lvl
| replace_regexp ("(?i)^(dbg|debug|D[0-9]?|20)$", "debug") at lvl
| replace_regexp ("(?i)^(ftl|fatal|F|60)$", "fatal") at lvl
| replace_regexp ("(?i)^(crit|critical)$", "critical") at lvl
| replace_regexp ("(?i)^(trace|10)$", "trace") at lvl
| replace_regexp ("(?i)^notice$", "notice") at lvl
| replace_regexp ("(?i)^panic$", "panic") at lvl
```

Why each part is the way it is, so nobody simplifies it back into the version that lied:

- **The pattern is quoted with backticks, not double quotes.** LogsQL's double-quoted string literal rejects `\x` escapes outright; a backtick-quoted literal passes them through to the regex engine, which is how the ANSI escape can be written at all.
- **It is anchored to the first 64 characters.** Docker splits any line over 16 KB into separate records of 16384 bytes and reassembles nothing. An unanchored search takes whatever level-looking word happens to sit in the middle of a continuation chunk, which turns one informational line into a phantom `error`. Every convention on this fleet puts its level well inside the window; a continuation chunk has none and correctly lands in the counter-query instead.
- **An ANSI escape counts as a word boundary on both sides.** A colourised level reads as `<esc>[32minfo<esc>[39m`, and the escape ends in the letter `m`, so a plain `[^a-zA-Z]` boundary never matches. Without this, `seerr` and `uptime-kuma` score zero levelled lines out of thousands.
- **The leading boundary is optional and the trailing one accepts end of line.** A line that starts with its level (`ERROR: ...`) and a line that ends with it (`... level=warn`) are both real and both unmatchable otherwise.
- **Two extra extractors cover the conventions with no level word at all**: MongoDB's single-letter severity (`"s":"I"`) in `komodo-mongo-db`, and pino's numeric level (`"level":30`) in `questarr`. They are anchored to their own literal key, so they can only fire on lines actually shaped that way.
- **The three extractors are coalesced by precedence, never concatenated.** The format-specific ones win over the tolerant word match, and `format if (lvl:"")` leaves an already-set value alone. Gluing them together instead would produce values like `error30` on a line where two extractors fire, which survives `lvl:*` but silently drops out of every `lvl:=error` query built on top - the exact class of silent hiding this whole pipeline exists to prevent.
- **The value is canonicalised.** LogsQL word filters are case-sensitive, so `ERROR`, `Error` and `error` would otherwise be three separate buckets and a bookmark on `lvl:error` would quietly miss two of them. Longer alternatives come first so `warning` is never shortened to `warn`.

## The error view

Every line the pipeline reads as an error or worse, across all containers.

```logsql
_time:24h <level pipeline> | filter lvl:in("error", "critical", "fatal", "panic")
```

`| stats by (app_name, lvl) count() as n | sort by (n) desc` gives the same thing as a per-container tally.

## The per-rider view

The five riders emit one JSON object per line with a fixed schema (#981), so their level needs no guessing - unpack it.

```logsql
_time:24h app_name:in("qbittorrent.qbittorrent-sorter", "qbittorrent.qbittorrent-tqm", "qbittorrent.qbittorrent-watcher", "qbittorrent.qbittorrent-uppollo-runner", "qbittorrent.qbittorrent-irc-watch") | unpack_json fields (level, event, component)
```

Add `| filter level:=error` for the same set the `RiderError` alerting rule sees, or `| stats by (event, component) count()` for the shape the alert groups on.

## The counter-query: lines the level pipeline did not match

The gap has to stay visible, because an unmatched line is excluded from the error view rather than treated as `info` (#980). A number that climbs means the pipeline needs a look, not that the fleet went quiet.

```logsql
_time:24h <level pipeline> | filter -lvl:* | stats by (app_name) count() as unmatched | sort by (unmatched) desc
```

The two haproxy access logs, `komodo.dockerproxy` and `komodo.dockerproxy-ro`, dominate this list by design: their lines carry no level and never will. Anything else appearing near the top is worth a sample.

## The drift check: values that are not one of the nine

The pipeline can only ever emit `trace`, `debug`, `info`, `notice`, `warn`, `error`, `critical`, `fatal` or `panic`. Anything else means an extractor produced something the canonicalisation does not know - a new convention, or two extractors colliding. It must return nothing.

```logsql
_time:24h <level pipeline> | filter lvl:* -lvl:in("trace", "debug", "info", "notice", "warn", "error", "critical", "fatal", "panic") | stats by (lvl) count() as n | sort by (n) desc
```

## Alerting

`vmalert` evaluates the rider rules every 15 minutes and hands anything firing to Alertmanager, which groups on `(event, component)` and repeats at most every 6 hours. Both run in this stack.

- Rules: the `vmalert_rules` config in `compose.yaml`.
- Silences and the current alert list: Alertmanager's own UI at `https://${ALERTMANAGER_EXTERNAL_URL}`.
- vmalert keeps its firing/pending state in memory only - there is no VictoriaMetrics instance to remote-write it to. A redeploy of this stack therefore resets it, and a firing alert re-notifies once afterwards. That is the price of the two services living in the log store's own stack.

Liveness is not here: VictoriaLogs cannot express absence, so a rider that stops emitting is watched by an Uptime Kuma push monitor instead (#983).
