---
type: Architecture
title: Stacks Overview
description: Stack-oriented Docker Compose deployment model — each stack is a self-contained directory with compose.yaml, .env.example, and stack-specific README
tags: [architecture, stacks, docker-compose, deployment-model]
resource: https://github.com/smoochy/homelab/tree/main/stacks
openwiki:
  roles: [architecture, domain]
  change_kinds: [structure, deployment]
  source_paths: [stacks/]
  symbols: [compose.yaml, .env.example, README.md]
  test_paths: []
  invariants: [Each stack directory is independently deployable, .env.example is the shared template, real .env stays local, .env.enc is tracked in Git]
  validation_commands: [docker compose -f stacks/<stack>/compose.yaml config]
---

# Stacks Overview

This repository uses a **stack-oriented deployment model**: each service or logical group lives in its own directory under `stacks/` with a complete, self-contained deployment definition.

## Stack Directory Structure

```
stacks/<stack-name>/
├── compose.yaml          # Docker Compose definition (required)
├── .env.example          # Tracked template with all configurable variables (required)
├── README.md             # Stack documentation: purpose, services, upstream links, config notes (required)
├── *.yml / *.yaml        # Optional: additional config files (e.g., traefik.yml, dynamic.yml)
├── scripts/              # Optional: stack-specific automation helpers
│   └── <script-name>/
│       ├── <script>.(sh|py)
│       ├── .env.example
│       ├── README.md
│       └── CHANGELOG.md
└── assets/               # Optional: images for README (e.g., SABnzbd mapping screenshots)
```

## Core Invariants

| Invariant | Description |
|-----------|-------------|
| **Independent deployability** | Each `stacks/<name>/compose.yaml` works standalone with its `.env` |
| **Template tracking** | `.env.example` is committed; real `.env` is `.gitignore`d |
| **Encrypted deployment** | `.env.enc` (SOPS/age encrypted) is committed; decrypted at deploy time via Komodo Pre Deploy |
| **Documentation co-location** | `README.md` explains purpose, services, upstream, config layout, scripts |

## Compose Conventions

- **Image pinning**: `image: repo:name@sha256:...` or `image: repo:name:tag` (Renovate manages updates)
- **Network**: Most stacks join the shared `smoonet` bridge network (created by `komodo` stack)
- **Traefik labels**: Services exposed via Traefik use Docker labels for routing, middleware, TLS
- **Env file**: `env_file: .env` or `env_file: ./compose.env` (Komodo writes runtime `.env` from `.env.enc`)
- **Volumes**: Host paths use `${APPDATA_ROOT:-/mnt/user/appdata}/<stack>` pattern or absolute Unraid paths

## Adding a New Stack

1. Create `stacks/<new-stack>/`
2. Add `compose.yaml` with service definitions
3. Add `.env.example` with all configurable variables (sensitive values blank)
4. Add `README.md` with:
   - Stack role/purpose
   - Services list
   - Upstream links (website, GitHub)
   - Config layout notes
   - Scripts section (if any)
4. Optionally add config files (`.yml`, `.conf`, etc.)
5. Optionally add `scripts/` for automation helpers
6. Verify: `docker compose -f stacks/<new-stack>/compose.yaml config`

## Stack Categories

### Edge & Networking
| Stack | Purpose | Key Config |
|-------|---------|------------|
| `traefik` | Core ingress, routing, CrowdSec plugin, geoip, Traefik Manager, log dashboard | `traefik.yml`, `dynamic.yml`, `CROWDSEC_*` env |
| `cloudflared` | Optional public tunnel for Komodo webhooks | Tunnel config, credentials |
| `adguard-home-unbound` | DNS filtering + recursive resolver | Upstream DNS, blocklists |
| `crowdsec` | LAPI for CrowdSec bouncer (used by Traefik plugin) | LAPI config, bouncer keys |

### Access, Control & Dashboards
| Stack | Purpose | Key Config |
|-------|---------|------------|
| `komodo` | Deployment control plane (Core + MongoDB + Periphery w/ SOPS+age + Docker Proxy) | `KOMODO_*`, `PERIPHERY_*`, `COMPOSE_KOMODO_IMAGE_TAG` |
| `authentik` | Identity provider (OIDC, SAML, LDAP) | `AUTHENTIK_*`, email, secret keys |
| `homepage` | Customizable dashboard | `HOMEPAGE_*`, service config YAML |
| `dozzle` | Log viewer for Docker containers | `DOZZLE_*`, log filtering |

### Media, Requests, Indexing & Adjacent Tooling
| Stack | Purpose | Key Config |
|-------|---------|------------|
| `radarr` | Movie collection manager | `RADARR_*`, quality profiles, indexers |
| `sonarr` | TV series collection manager | `SONARR_*`, quality profiles, indexers |
| `sabnzbd` | Usenet downloader | `SABNZBD_*`, categories, scripts |
| `prowlarr` | Indexer manager for *arr apps | `PROWLARR_*`, indexer configs |
| `seerr` / `episeerr` | Request frontends for *arr | `SEERR_*`, `EPISEERR_*`, TMDB, *arr connections |
| `plex` | Media server | `PLEX_*`, claim token, transcode |
| `tautulli` | Plex monitoring & stats | `TAUTULLI_*`, Plex connection |
| `tracearr` | *arr request tracing | `TRACEARR_*` |
| `umlautadaptarr` | Umlaut handling for *arr | `UMLEADAPTARR_*` |
| `notifiarr` | Notification aggregation | `NOTIFIARR_*`, service webhooks |

### Utility & Infrastructure
| Stack | Purpose | Key Config |
|-------|---------|------------|
| `mosquitto` | MQTT broker | `MOSQUITTO_*`, auth, websockets |
| `registry` | Docker registry | `REGISTRY_*`, storage, auth |
| `speedtest-tracker` | Internet speed history | `SPEEDTEST_*`, schedule |
| `homebridge` | HomeKit bridge | `HOMEBRIDGE_*`, plugins, config |
| `changedetection-io` | Website change monitoring | `CHANGEDETECTION_*`, watches |
| `cloudberry-backup` | Backup client | `CLOUDBERRY_*`, plans, storage |
| `uptime-kuma` | Uptime monitoring | `UPTIME_KUMA_*`, monitors, notifications |
| `apprise` | Notification gateway | `APPRISE_*`, service URLs |
| `duplicati` | Backup | `DUPLICATI_*`, backup sets |
| `questarr` | Quest management | `QUESTARR_*` |
| `caddy` | Alternative reverse proxy (custom modules) | `CADDY_*`, Caddyfile, modules |

## Shared Network: `smoonet`

The `komodo` stack's `compose.yaml` creates the `smoonet` bridge network on first deploy:

```yaml
networks:
  smoonet:
    name: smoonet
    external: false
```

Other stacks reference it as `external: true`:

```yaml
networks:
  smoonet:
    external: true
```

This allows inter-stack communication (e.g., Traefik → service containers) without hardcoding host ports.

## Environment Variable Patterns

### Standard Variables (per stack)
- `<STACK>_EXTERNAL_URL` — Public hostname (Traefik route)
- `<STACK>_INTERNAL_URL` — Internal Docker URL (for inter-service calls)
- `<STACK>_UNRAID_WEBGUI_URL` — Unraid WebGUI link (for Homepage)
- `<STACK>_SERVICE` — Service name for Traefik labels

### Sensitive Variables (blank in `.env.example`)
- API tokens (`CF_DNS_API_TOKEN`, `RADARR_API_KEY`, etc.)
- Secrets (`SPECIAL_HEADER_SECRET`, `KOMODO_PASSKEY`, `KOMODO_JWT_SECRET`, etc.)
- Database passwords (`KOMODO_DB_PASSWORD`, etc.)
- OAuth credentials (`KOMODO_GITHUB_OAUTH_SECRET`, etc.)

### Komodo-Specific Variables
- `KOMODO_REPO_NAME` — Repo name for absolute host paths on Unraid
- `COMPOSE_KOMODO_IMAGE_TAG` — Pinned Komodo image tag
- `KOMODO_FIRST_SERVER` — Periphery address for Core
- `KOMODO_WEBHOOK_SECRET` — GitHub webhook validation

## Deployment via Komodo

Each stack is deployed as a **Komodo Resource** with:

| Field | Value |
|-------|-------|
| **Run Directory** | `stacks/<stack>` (relative to repo checkout) |
| **Config Files** | `.env.enc` (and any stack-specific config files like `Caddyfile`) |
| **Requires** | `Redeploy` |
| **Pre Deploy** | `sops --input-type dotenv --output-type dotenv -d .env.enc > .env` |

<!-- openwiki: broken internal link [../workflows/encrypted-deployment.md] file "../workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
See [Encrypted Deployment Workflow](../workflows/encrypted-deployment.md) for full details.

## Validation

```bash
# Validate a single stack's compose file
docker compose -f stacks/traefik/compose.yaml config

# Validate all stacks (from repo root)
for d in stacks/*/; do
  echo "=== ${d} ==="
  docker compose -f "${d}compose.yaml" config >/dev/null && echo "OK" || echo "FAIL"
done
```

## Related Pages

- [Quickstart](../quickstart.md) — Repository overview and navigation
<!-- openwiki: broken internal link [../workflows/encrypted-deployment.md] file "../workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Encrypted Deployment Workflow](../workflows/encrypted-deployment.md) — SOPS/age/Komodo end-to-end flow
- [Edge & Networking](../domain/edge-networking.md) — Traefik, Cloudflared, AdGuard, CrowdSec
- [Access & Control](../domain/access-control.md) — Komodo, Authentik, Homepage, Dozzle
<!-- openwiki: broken internal link [../domain/media-automation.md] file "../domain/media-automation.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Media Automation](../domain/media-automation.md) — *Arr stacks, Plex, requests
<!-- openwiki: broken internal link [../domain/utility-infrastructure.md] file "../domain/utility-infrastructure.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Utility & Infrastructure](../domain/utility-infrastructure.md) — MQTT, registry, monitoring, backup