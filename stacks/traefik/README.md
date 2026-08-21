# Traefik

> Core ingress, routing, and edge security stack for the homelab network

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `traefik`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `traefik`
- `geoipupdate`
- `traefik-manager`
- `traefik-log-dashboard`
- `traefik-log-dashboard-agent`

## Upstream

### `traefik`

- Website: [https://traefik.io/traefik/](https://traefik.io/traefik/)
- GitHub: [https://github.com/traefik/traefik](https://github.com/traefik/traefik)

### `geoipupdate`

- Website: [https://dev.maxmind.com/geoip/updating-databases/](https://dev.maxmind.com/geoip/updating-databases/)
- GitHub: [https://github.com/maxmind/geoipupdate](https://github.com/maxmind/geoipupdate)

### `traefik-manager`

- Website: [https://traefik-manager.xyzlab.dev/](https://traefik-manager.xyzlab.dev/)
- GitHub: [https://github.com/chr0nzz/traefik-manager](https://github.com/chr0nzz/traefik-manager)

### `traefik-log-dashboard`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard](https://github.com/hhftechnology/traefik-log-dashboard)

### `traefik-log-dashboard-agent`

- Website: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)
- GitHub: [https://github.com/hhftechnology/traefik-log-dashboard-agent](https://github.com/hhftechnology/traefik-log-dashboard-agent)

## Scripts

- [Cloudflare Trusted IP Sync and Config Backup Script](./scripts/cloudflare_trusted_ips/README.md): Host-side helper that refreshes Cloudflare trusted IPs, republishes the matching Traefik env artifacts, and creates dated backups of `traefik.yml` and `dynamic.yml` before each run.

## Config Layout

- `traefik.yml` loads the file provider from the `rules/` directory; no HTTP provider endpoint is enabled. Every file in that directory is merged, so a new set of routers is added by dropping a file in, not by editing an existing one.
- `rules/base.yml` stores the repo-managed baseline middlewares, routers, and services.
- `rules/crowdsec-manager.yml` is reserved for the dynamic configuration `crowdsec-manager` generates; it stays a comment-only file until that happens.
- `dynamic.yml` is no longer read by Traefik. It is still mounted into `traefik-manager`, which points at it through `TRAEFIK_DYNAMIC_CONFIG`, and it holds only the `traefik-manager` router itself.
- Traefik reads Docker through the read-only socket proxy: `providers.docker.endpoint` is `tcp://dockerproxy-ro:2375`, and `DOCKER_HOST` in `compose.yaml` matches it. `DOCKER_HOST` wins over the `endpoint:` setting, so moving the endpoint needs a recreate, not a restart (measured on 2026-08-19).
- `traefik-manager` provides a web UI for route, middleware, service, certificate, log, and static configuration operations against the same Traefik runtime files.
- `scripts/cloudflare_trusted_ips` stores the host-side automation that refreshes the managed Cloudflare IP block, republishes the matching `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` value through `stacks/traefik/.env.enc` and `stacks/traefik/.env.example`, and creates dated backups of `traefik.yml` and `dynamic.yml` under `/mnt/user/appdata/traefik/backups` before each run.

## CrowdSec Plugin

This stack uses the official CrowdSec Traefik plugin for edge remediation instead of a dedicated forward-auth sidecar container.

The plugin loads from disk, never from the registry. The remote path is not usable here: `plugins.traefik.io` answers the archive download in 13-30s against a client timeout of roughly 10s that Traefik does not expose as a setting, and pre-seeding the archive does not help because the registry ignores the conditional `X-Plugin-Hash` header and Traefik wipes the seeded tree on a failed download. `experimental.localPlugins` is Traefik's supported offline path and is what runs here.

- `traefik.yml` registers `github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin` under `experimental.localPlugins`.
- The sources live on the host under `/mnt/user/appdata/traefik/plugins-local` and are mounted read-only into the container at `/plugins-local`, which is the path Traefik resolves relative to its working directory. The mount is required, because a container-internal symlink lives in the writable layer and is lost on every recreate.
- The `traefik` service defines the `crowdsec-bouncer` middleware via Docker labels so the LAPI key can be injected from `.env`.
- `rules/base.yml` applies `crowdsec-bouncer@docker` only on `chain-external` and `chain-external-bypass`.
- `chain-internal` and `chain-internal-bypass` intentionally stay CrowdSec-free.
- `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` must stay aligned with `websecure-external.forwardedHeaders.trustedIPs`.

The `traefik-warp` plugin was removed for good and no longer loads. It fetched the Cloudflare and CloudFront IP ranges over HTTPS synchronously inside its `New()`, and Traefik calls `New()` once per router, so 126 routers at roughly 2s each made every Traefik start serve 404 on all Docker routers for three minutes. It also earned nothing: the real client IP behind Cloudflare is already recovered statically twice over, by `websecure-external.forwardedHeaders.trustedIPs` and by the bouncer's own `forwardedheaderstrustedips`. On a failed fetch it falls back to trusting every IP.
