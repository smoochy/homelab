---
type: Overview
title: Homelab Wiki Quickstart
description: Entry point for the homelab repository wiki — stack-oriented Docker Compose deployments with encrypted env handling, Komodo deployment, and automation scripts
tags: [homelab, docker, komodo, sops, quickstart]
resource: https://github.com/smoochy/homelab
openwiki:
  roles: [repository, architecture]
  change_kinds: [structure, navigation]
  source_paths: [README.md]
  symbols: []
  test_paths: []
  invariants: []
  validation_commands: []
---

# Homelab Wiki Quickstart

This wiki documents a **Docker-based homelab** built around stack-level `compose.yaml` files, tracked `.env.example` templates, and a deployment workflow using **Komodo**, **SOPS/age**, and **File Watcher** encryption.

> **Repository**: <https://github.com/smoochy/homelab>  
> **Companion**: `komodo-periphery-sops-age` (custom Periphery image), `caddy-modules` (custom Caddy builds)

---

## What This Repository Contains

| Area | Description |
|------|-------------|
| [`stacks/`](./architecture/stacks-overview.md) | 27 independent stack directories, each with `compose.yaml`, `.env.example`, `README.md` |
<!-- openwiki: broken internal link [./workflows/encrypted-deployment.md] file "./workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [`docs/`](./workflows/encrypted-deployment.md) | Cross-stack deployment guides (SOPS/age/Komodo, GitHub workflows) |
| Stack scripts | Per-stack automation helpers (Radarr auto-tag, SABnzbd monitors, ISO extraction, history cleanup, Uptime Kuma maintenance) |

---

## Navigation by Intent

| Change Area / User Intent | Relevant Wiki Page | Source Entry Points | Key Symbols / Types | Focused Tests | Minimal Validation |
|---------------------------|-------------------|---------------------|---------------------|---------------|-------------------|
| Understand repo layout & stack model | [Architecture: Stacks Overview](./architecture/stacks-overview.md) | `README.md`, `stacks/*/` | `compose.yaml`, `.env.example` | — | `ls stacks/` |
<!-- openwiki: broken internal link [./workflows/encrypted-deployment.md] file "./workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Deploy a stack with encrypted env | [Workflows: Encrypted Deployment](./workflows/encrypted-deployment.md) | `docs/sops-age-komodo.md` | `.env`, `.env.enc`, `sops`, `age`, Komodo Pre Deploy | — | Verify `.vscode/.scripts/` exists |
| Add or modify a service stack | [Architecture: Stacks Overview](./architecture/stacks-overview.md) | `stacks/<new-stack>/` | `compose.yaml`, `.env.example`, `README.md` | — | `docker compose -f stacks/<stack>/compose.yaml config` |
| Configure Traefik ingress & CrowdSec | [Domain: Edge & Networking](./domain/edge-networking.md) | `stacks/traefik/` | `traefik.yml`, `dynamic.yml`, `CROWDSEC_*` env | — | Check Traefik dashboard |
| Set up Komodo control plane | [Domain: Access & Control](./domain/access-control.md) | `stacks/komodo/` | `core`, `periphery`, `mongo`, `dockerproxy` | — | `docker logs komodo-core` |
<!-- openwiki: broken internal link [./integrations/radarr-auto-tag.md] file "./integrations/radarr-auto-tag.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Automate Radarr watched cleanup | [Integrations: Radarr Auto-Tag](./integrations/radarr-auto-tag.md) | `stacks/radarr/scripts/auto_tag/` | `radarr_movie.py`, Tautulli `Stop` trigger | — | `docker exec tautulli python3 radarr_movie.py --run-pending` |
<!-- openwiki: broken internal link [./integrations/sabnzbd-speed-monitor.md] file "./integrations/sabnzbd-speed-monitor.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Monitor SABnzbd throughput & recover | [Integrations: SABnzbd Speed Monitor](./integrations/sabnzbd-speed-monitor.md) | `stacks/sabnzbd/scripts/monitor_sab_speed/` | `monitor_sab_speed.sh`, `RECOVERY_METHOD` | — | `FORCE_LOW_SPEED_TEST=1 RESTART_ENABLED=0 ./monitor_sab_speed.sh` |
<!-- openwiki: broken internal link [./integrations/sabnzbd-iso-extractor.md] file "./integrations/sabnzbd-iso-extractor.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Extract ISOs in SABnzbd post-process | [Integrations: SABnzbd ISO Extractor](./integrations/sabnzbd-iso-extractor.md) | `stacks/sabnzbd/scripts/extract_iso/` | `extract_iso.sh`, `7z`/`bsdtar` | — | SABnzbd history log |
<!-- openwiki: broken internal link [./integrations/sabnzbd-history-cleanup.md] file "./integrations/sabnzbd-history-cleanup.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Clean SABnzbd history by category | [Integrations: SABnzbd History Cleanup](./integrations/sabnzbd-history-cleanup.md) | `stacks/sabnzbd/scripts/delete_item_from_history/` | `delete_item.sh`, `delete_items_worker.sh` | — | Check queue file |
<!-- openwiki: broken internal link [./integrations/uptime-kuma-maintenance.md] file "./integrations/uptime-kuma-maintenance.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Wrap appdata.backup with Uptime Kuma | [Integrations: Uptime Kuma Maintenance](./integrations/uptime-kuma-maintenance.md) | `stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/` | `appdata_backup_kuma_helper.sh`, pre/post-run hooks | — | `./appdata_backup_kuma_helper.sh start` |
<!-- openwiki: broken internal link [./workflows/github-automation.md] file "./workflows/github-automation.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| Understand Renovate PR automation | [Workflows: GitHub Automation](./workflows/github-automation.md) | `docs/github-workflows/README.md`, `.github/workflows/` | `renovate.yaml`, `config.js`, `pr-age-gate`, `timed-pr-automerge` | — | Check PR checks |

---

## Repository Layout

```text
homelab/
├── README.md                    # This repo's overview
├── docs/
│   ├── README.md                # Docs index
│   ├── sops-age-komodo.md       # Encrypted deployment workflow
│   └── github-workflows/        # Renovate & public mirror docs
│       ├── README.md
│       └── metabase/
├── stacks/                      # One folder per stack/app
│   ├── traefik/                 # Ingress, routing, CrowdSec, geoip, log dashboard
│   ├── komodo/                  # Deployment control plane (core + periphery+sops+age)
│   ├── radarr/                  # + auto-tag automation script
│   ├── sonarr/
│   ├── sabnzbd/                 # + speed monitor, ISO extractor, history cleanup
│   ├── prowlarr/
│   ├── seerr/
│   ├── episeerr/
│   ├── plex/
│   ├── tautulli/
│   ├── tracearr/
│   ├── umlautadaptarr/
│   ├── notifiarr/
│   ├── cloudflared/
│   ├── adguard-home-unbound/
│   ├── crowdsec/
│   ├── authentik/
│   ├── homepage/
│   ├── dozzle/
│   ├── mosquitto/
│   ├── registry/
│   ├── speedtest-tracker/
│   ├── homebridge/
│   ├── changedetection-io/
│   ├── cloudberry-backup/
│   ├── uptime-kuma/             # + appdata.backup maintenance helper
│   ├── apprise/
│   ├── duplicati/
│   ├── questarr/
│   └── caddy/
└── .github/
    ├── workflows/
    │   ├── openwiki-update.yaml
    │   └── renovate.yaml
    └── dependabot.yml
```

---

## Stack Coverage by Category

### Edge & Networking
- **traefik** — Core ingress, routing, CrowdSec plugin, geoipupdate, Traefik Manager, log dashboard
- **cloudflared** — Optional public endpoint for Komodo webhooks
- **adguard-home-unbound** — DNS filtering + recursive resolver
- **crowdsec** — LAPI for CrowdSec bouncer (referenced by Traefik plugin)

### Access, Control & Dashboards
- **komodo** — Deployment control plane (Core + MongoDB + Periphery w/ SOPS+age + Docker Proxy)
- **authentik** — Identity provider
- **homepage** — Dashboard
- **dozzle** — Log viewer

### Media, Requests, Indexing & Adjacent Tooling
- **radarr** + **auto-tag** script (Tautulli → Radarr watched cleanup)
- **sonarr**
- **sabnzbd** + **speed monitor**, **ISO extractor**, **history cleanup** scripts
- **prowlarr** — Indexer manager
- **seerr** / **episeerr** — Request frontends
- **plex** + **tautulli** — Media server + monitoring
- **tracearr** / **umlautadaptarr** / **notifiarr** — Adjacent tooling

### Utility & Infrastructure
- **mosquitto** — MQTT broker
- **registry** — Docker registry
- **speedtest-tracker** — Internet speed history
- **homebridge** — HomeKit bridge
- **changedetection-io** — Website change monitoring
- **cloudberry-backup** — Backup client
- **uptime-kuma** + **maintenance helper** — Uptime monitoring w/ appdata.backup integration
- **apprise** — Notification gateway
- **duplicati** — Backup
- **questarr** — Quest management
- **caddy** — Alternative reverse proxy (custom modules)

---

## Using This Repository as a Base

1. **Pick stacks** from `stacks/` matching your target environment
2. **Copy `.env.example`** → `.env` and fill in local values
3. **Adjust host paths, domains, networking** for your deployment
<!-- openwiki: broken internal link [./workflows/encrypted-deployment.md] file "./workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
4. **Follow** [Encrypted Deployment Workflow](./workflows/encrypted-deployment.md) for SOPS/age/Komodo
5. **Deploy** selected stacks via Komodo or plain Docker Compose

---

## Key Documentation Pages

| Page | Purpose |
|------|---------|
| [Architecture: Stacks Overview](./architecture/stacks-overview.md) | Stack model, compose structure, env template pattern |
| [Domain: Edge & Networking](./domain/edge-networking.md) | Traefik, Cloudflared, AdGuard, CrowdSec details |
| [Domain: Access & Control](./domain/access-control.md) | Komodo, Authentik, Homepage, Dozzle |
<!-- openwiki: broken internal link [./domain/media-automation.md] file "./domain/media-automation.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Domain: Media Automation](./domain/media-automation.md) | *Arr stack, Plex, requests, indexing |
<!-- openwiki: broken internal link [./domain/utility-infrastructure.md] file "./domain/utility-infrastructure.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Domain: Utility & Infrastructure](./domain/utility-infrastructure.md) | MQTT, registry, monitoring, backup, home automation |
<!-- openwiki: broken internal link [./workflows/encrypted-deployment.md] file "./workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Workflows: Encrypted Deployment](./workflows/encrypted-deployment.md) | SOPS/age/File Watcher/Komodo end-to-end flow |
<!-- openwiki: broken internal link [./workflows/github-automation.md] file "./workflows/github-automation.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Workflows: GitHub Automation](./workflows/github-automation.md) | Renovate, PR age gates, public mirror, Metabase flow |
<!-- openwiki: broken internal link [./integrations/radarr-auto-tag.md] file "./integrations/radarr-auto-tag.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Integrations: Radarr Auto-Tag](./integrations/radarr-auto-tag.md) | Tautulli-triggered watched verification & deferred cleanup |
<!-- openwiki: broken internal link [./integrations/sabnzbd-speed-monitor.md] file "./integrations/sabnzbd-speed-monitor.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Integrations: SABnzbd Speed Monitor](./integrations/sabnzbd-speed-monitor.md) | Host-side throughput monitoring & Komodo/Docker recovery |
<!-- openwiki: broken internal link [./integrations/sabnzbd-iso-extractor.md] file "./integrations/sabnzbd-iso-extractor.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Integrations: SABnzbd ISO Extractor](./integrations/sabnzbd-iso-extractor.md) | Post-processing ISO extraction with 7z/bsdtar |
<!-- openwiki: broken internal link [./integrations/sabnzbd-history-cleanup.md] file "./integrations/sabnzbd-history-cleanup.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Integrations: SABnzbd History Cleanup](./integrations/sabnzbd-history-cleanup.md) | Category-filtered history deletion via queue + worker |
<!-- openwiki: broken internal link [./integrations/uptime-kuma-maintenance.md] file "./integrations/uptime-kuma-maintenance.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| [Integrations: Uptime Kuma Maintenance](./integrations/uptime-kuma-maintenance.md) | appdata.backup pre/post-run hook wrapper for Kuma |

---

## Backlog

No backlog items — initial documentation covers all discovered components and workflows.

---

## Companion Repositories

- **komodo-periphery-sops-age**: <https://github.com/smoochy/komodo-periphery-sops-age> — Komodo Periphery image with `sops` and `age` preinstalled
- **caddy-modules**: <https://github.com/smoochy/caddy-modules> — Custom Caddy image builds used by the `caddy` stack