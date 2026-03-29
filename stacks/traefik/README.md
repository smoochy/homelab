# Traefik

> Core ingress, routing, and edge security stack for the homelab network

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `traefik`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `traefik`
- `geoipupdate`
- `traefik-middleware-manager`
- `traefik-log-dashboard`
- `traefik-log-dashboard-agent`

## Upstream

### `traefik`

- Website: [https://traefik.io/traefik/](https://traefik.io/traefik/)
- GitHub: [https://github.com/traefik/traefik](https://github.com/traefik/traefik)

### `geoipupdate`

- Website: [https://dev.maxmind.com/geoip/updating-databases/](https://dev.maxmind.com/geoip/updating-databases/)
- GitHub: [https://github.com/maxmind/geoipupdate](https://github.com/maxmind/geoipupdate)

### `traefik-middleware-manager`

- Website: [https://github.com/hhftechnology/middleware-manager](https://github.com/hhftechnology/middleware-manager)
- GitHub: [https://github.com/hhftechnology/middleware-manager](https://github.com/hhftechnology/middleware-manager)

### `traefik-log-dashboard`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)

### `traefik-log-dashboard-agent`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)

## Scripts

- [Cloudflare Trusted IP Sync and Config Backup Script](./scripts/cloudflare_trusted_ips/README.md): Host-side helper that refreshes Cloudflare trusted IPs, republishes the matching Traefik env artifacts, and creates dated backups of `traefik.yml` and `dynamic.yml` before each run.

## Config Layout

- `traefik.yml` loads the file provider from `dynamic.yml` and keeps the HTTP provider endpoint for `traefik-middleware-manager`.
- `dynamic.yml` stores the repo-managed baseline middlewares, routers, and services for the single-file setup.
- `traefik-middleware-manager` stays in the stack in API-only mode.
- `scripts/cloudflare_trusted_ips` stores the host-side automation that refreshes the managed Cloudflare IP block, republishes the matching `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` value through `stacks/traefik/.env.enc` and `stacks/traefik/.env.example`, and creates dated backups of `traefik.yml` and `dynamic.yml` under `/mnt/user/appdata/traefik/backups` before each run.
## CrowdSec Plugin

This stack uses the official CrowdSec Traefik plugin for edge remediation instead of a dedicated forward-auth sidecar container.

- `traefik.yml` registers the experimental plugin `github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin`.
- The `traefik` service defines the `crowdsec-bouncer` middleware via Docker labels so the LAPI key can be injected from `.env`.
- `dynamic.yml` applies `crowdsec-bouncer@docker` only on `chain-external` and `chain-external-bypass`.
- `chain-internal` and `chain-internal-bypass` intentionally stay CrowdSec-free.
- `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` must stay aligned with `websecure-external.forwardedHeaders.trustedIPs`.
