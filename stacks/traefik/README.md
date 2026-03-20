# Traefik

> Core ingress, routing, and edge security stack for the homelab network

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `traefik`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `traefik`
- `geoipupdate`
- `traefik-log-dashboard`
- `traefik-log-dashboard-agent`

## Upstream

### `traefik`

- Website: [https://traefik.io/traefik/](https://traefik.io/traefik/)
- GitHub: [https://github.com/traefik/traefik](https://github.com/traefik/traefik)

### `geoipupdate`

- Website: [https://dev.maxmind.com/geoip/updating-databases/](https://dev.maxmind.com/geoip/updating-databases/)
- GitHub: [https://github.com/maxmind/geoipupdate](https://github.com/maxmind/geoipupdate)

### `traefik-log-dashboard`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)

### `traefik-log-dashboard-agent`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)
