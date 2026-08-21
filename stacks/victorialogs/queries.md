# Saved LogsQL queries

The store has no server-side saved queries, so these live here and as bookmarks in Homepage. Paste them into VMUI at `https://${TRAEFIK_EXTERNAL_URL}/select/vmui/`.

Two things to know before reading any of them:

- `app_name` is `<compose project>.<container name>`, built from the syslog driver's tag (#972). The stack is in the name because the driver emits no RFC5424 structured data.
- Ingest is lossy UDP by design. A missing line means the datagram never arrived, not that the event never happened - so a query returning nothing is weak evidence, and an alert that never fired is not proof that nothing broke.

## The error view

Every line the fleetwide level pattern reads as an error, across all containers, most recent first. The pattern is deliberately tolerant: it takes the level word nearest the start of the line, which covers the four conventions found across the fleet in #980.

```logsql
_time:24h | extract_regexp "(?i)\\b(?P<level>trace|debug|info|warn|warning|error|fatal|panic)\\b" | filter level:~"(?i)^(error|fatal|panic)$"
```

## The per-rider view

The five riders emit one JSON object per line with a fixed schema (#981), so their level needs no guessing - unpack it.

```logsql
_time:24h app_name:in("qbittorrent.qbittorrent-sorter", "qbittorrent.qbittorrent-tqm", "qbittorrent.qbittorrent-watcher", "qbittorrent.qbittorrent-uppollo-runner", "qbittorrent.qbittorrent-irc-watch") | unpack_json fields (level, event, component)
```

Add `| filter level:=error` for the same set the `RiderError` alerting rule sees, or `| stats by (event, component) count()` for the shape the alert groups on.

## The counter-query: lines the level pattern did not match

The gap has to stay visible, because an unmatched line is excluded from the error view rather than treated as `info` (#980). A number that climbs means the pattern needs a look, not that the fleet went quiet.

```logsql
_time:24h | extract_regexp "(?i)\\b(?P<level>trace|debug|info|warn|warning|error|fatal|panic)\\b" | filter level:"" | stats by (app_name) count() as unmatched | sort by (unmatched) desc
```

## Alerting

`vmalert` evaluates the rider rules every 15 minutes and hands anything firing to Alertmanager, which groups on `(event, component)` and repeats at most every 6 hours. Both run in this stack.

- Rules: the `vmalert_rules` config in `compose.yaml`.
- Silences and the current alert list: Alertmanager's own UI at `https://${ALERTMANAGER_EXTERNAL_URL}`.
- vmalert keeps its firing/pending state in memory only - there is no VictoriaMetrics instance to remote-write it to. A redeploy of this stack therefore resets it, and a firing alert re-notifies once afterwards. That is the price of the two services living in the log store's own stack.

Liveness is not here: VictoriaLogs cannot express absence, so a rider that stops emitting is watched by an Uptime Kuma push monitor instead (#983).
