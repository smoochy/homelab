# VictoriaLogs

> Long-term container log store with full-text search and level filtering, kept independent of container lifetimes

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `victorialogs`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `victorialogs`
- `vmalert`
- `alertmanager`

## Upstream

- Website: [https://docs.victoriametrics.com/victorialogs/](https://docs.victoriametrics.com/victorialogs/)
- GitHub: [https://github.com/VictoriaMetrics/VictoriaLogs](https://github.com/VictoriaMetrics/VictoriaLogs)
