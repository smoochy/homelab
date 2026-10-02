# VictoriaLogs

> Long-term container log store with full-text search and level filtering, kept independent of container lifetimes

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `victorialogs`.

## Services

- `probe-busybox` - one-shot init container that copies a static busybox into the `probe-bin` volume, so the distroless `victorialogs` image has a probe binary for its healthcheck
- `victorialogs`
- `vmalert` - evaluates the rider rules against the store every 15 minutes
- `alertmanager` - groups, suppresses and delivers them to Discord; its UI is the place to silence one

The rules and the Alertmanager configuration live inline in `compose.yaml`, because Komodo deploys that file and nothing else beside it. Saved queries and what the alerting does and does not cover are in [`queries.md`](queries.md).

## Upstream

- Website: [https://docs.victoriametrics.com/victorialogs/](https://docs.victoriametrics.com/victorialogs/)
- GitHub: [https://github.com/VictoriaMetrics/VictoriaLogs](https://github.com/VictoriaMetrics/VictoriaLogs)
