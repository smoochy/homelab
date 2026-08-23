---
type: Reference
title: Stacks
description: Overview of all Docker Compose stacks in the repository, their categories, and purpose.
tags: [stacks, docker-compose, services]
---

# Stacks

The `stacks/` directory contains one subdirectory per service or application stack. Each stack includes:

- A `compose.yaml` file defining the Docker Compose services.
- A tracked `.env.example` file serving as the configuration template.
- An optional `README.md` with upstream links and stack-specific context.
- Optional `scripts/` directory for stack-specific automation workflows.

Stacks are designed to be reusable and modular. You can deploy individual stacks independently or combine them as needed.

## Categories

Stacks are grouped into the following categories based on their function in a typical homelab:

### Edge and Networking
Services handling traffic routing, DNS, ad blocking, and network security.

- `traefik` – Reverse proxy and load balancer.
- `cloudflared` – Cloudflare Tunnel client for secure remote access.
- `adguard-home-unbound` – Combined AdGuard Home (DNS-based ad blocking) and Unbound (recursive DNS resolver).
- `crowdsec` – Collaborative security engine for IP reputation and threat prevention.
- `caddy` – Alternative reverse proxy with automatic HTTPS.

### Access, Control, and Dashboards
Services for authentication, visualization, and lab-wide control panels.

- `komodo` – Deployment tool used in this repository (see [Komodo](/openwiki/komodo.md)).
- `authentik` – Open-source identity provider (IdP) for authentication and authorization.
- `homepage` – Customizable homepage/dashboard for homelab services.
- `dozzle` – Real-time log viewer for Docker containers.

### Media, Requests, Indexing, and Adjacent Tooling
Services for media management, automated downloading, metadata enrichment, and related tooling.

- `radarr` – Automated movie downloading and library management.
- `sonarr` – Automated TV show downloading and library management.
- `sabnzbd` – NZB downloader for Usenet.
- `prowlarr` – Indexer manager/proxy for Sonarr, Radarr, etc.
- `seerr` – Request management interface for media services (Radarr, Sonarr, etc.).
- `episeerr` – Companion to Seerr for episode-level requests and tracking.
- `plex` – Media server for streaming organized libraries.
- `tautulli` – Monitoring and tracking tool for Plex usage statistics.
- `tracearr` – Dependency checker for media arr applications.
- `umlautadaptarr` – Metadata and subtitle enhancer for media arr applications.
- `notifiarr` – Notification and automation bridge for arr applications.
- `questarr` – Quest tracking and management for media arr applications (e.g., Sonarr/Radarr quests).

### Utility and Infrastructure Services
General-purpose services providing messaging, container registry, system monitoring, and other utilities.

- `mosquitto` – Lightweight MQTT message broker for IoT and automation.
- `registry` – Private Docker registry for storing and distributing container images.
- `speedtest-tracker` – Automated internet speed testing and historical tracking.
- `homebridge` – Bridge to expose non-HomeKit devices to Apple HomeKit.
- `changedetection-io` – Website change detection and notification service.
- `cloudberry-backup` – Backup utility for cloud and local storage targets.
- `uptime-kuma` – Self-hosted monitoring tool with push notifications and status pages.
- `apprise` – Notification service supporting dozens of platforms and services.
- `duplicati` – Backup client supporting encrypted, incremental backups to various destinations.

### Monitoring and Logging
Services focused on observability, health checks, and log aggregation.

- `stack-health` – Aggregates health status from other stacks and provides a unified overview.
- `victorialogs` – Log storage and visualization system (based on VictoriaMetrics and Grafana).

## Using a Stack

Each stack is self-contained. To use a stack:

1. Copy the stack's `.env.example` to a local `.env` file (ignored by Git via `.gitignore`).
2. Edit `.env` with your configuration values.
3. If using SOPS/age encryption (recommended), encrypt `.env` to `.env.enc` (see [SOPS & age Encryption](/openwiki/sops-age.md)).
4. Deploy with Komodo (see [Deployment Workflow](/openwiki/deployment.md)) or directly with Docker Compose.
5. Refer to the stack's `README.md` (in `stacks/<stack>/README.md`) for upstream links and specific notes.

## Adding a New Stack

To add a new stack to the repository:

1. Create a new directory under `stacks/` for your service.
2. Add a `compose.yaml` defining the service(s).
3. Add a tracked `.env.example` with configuration placeholders.
4. Optionally add a `README.md` with context and links.
5. Optionally add a `scripts/` directory for automation.
6. Update this document (`/openwiki/stacks.md`) to include the new stack in the appropriate category.

## Source

- Source directory: `/stacks`
- Each stack's source: `/stacks/<stack>/`