---
type: concept
title: Media Domain
description: Documentation of the media stacks (Plex, Radarr, Sonarr, Prowlarr) responsible for media acquisition, indexing, and streaming in the homelab.
tags: [media, plex, radarr, sonarr, prowlarr]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-519e20d7752ae9e28e1bec36
    resource: repo://stacks/plex/compose.yaml
  - id: openwiki-source-a4cd1997867c9a538f369a14
    resource: repo://stacks/plex/README.md
  - id: openwiki-source-49768c34f7d88030f3fa9a83
    resource: repo://stacks/prowlarr/compose.yaml
  - id: openwiki-source-4a01feb1d3ba37085779a541
    resource: repo://stacks/prowlarr/README.md
  - id: openwiki-source-d05539273d4d5a06fdb00d0f
    resource: repo://stacks/radarr/compose.yaml
  - id: openwiki-source-4be8fbf45cc2f26d25187a81
    resource: repo://stacks/radarr/README.md
  - id: openwiki-source-2de6ea2c9e6a38d6b0dc92ad
    resource: repo://stacks/sonarr/compose.yaml
  - id: openwiki-source-db778a8377be44e043a86881
    resource: repo://stacks/sonarr/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---
# Media Domain

This document describes the media acquisition, indexing, and streaming stacks in the homelab architecture.

## Overview

The media domain consists of four primary stacks:
- **Plex**: Media server for streaming and library management
- **Radarr**: Movie acquisition and library management
- **Sonarr**: Series acquisition and library management
- **Prowlarr**: Indexer manager shared across Radarr and Sonarr

These stacks work together to automate media discovery, download, organization, and streaming.

## Stack Responsibilities

### Plex
Plex serves as the central media server, providing:
- Media library organization and metadata enrichment
- Streaming capabilities to local and remote clients
- Media scanning and automatic library updates
- Transcoding for device compatibility
- Remote access via Plex.tv

**Entrypoints**:
- Web UI: https://plex.<domain> (via Traefik)
- Direct LAN access: http://192.0.2.103:32400 (br0 network)
- API: Available on same ports for automation

**Network Configuration**:
- Connected to both `br0` (static IP 192.0.2.103) for client traffic and `smoonet` for internal Docker communication
- Healthcheck: `/identity` endpoint via curl

### Radarr
Radarr handles movie-specific acquisition and library management:
- Monitors configured indexers (via Prowlarr) for movie releases
- Interfaces with download clients (external to this stack) to fetch movies
- Renames, organizes, and moves completed downloads to Plex library folders
- Triggers library scans in Plex upon successful import
- Manages movie metadata, upgrades, and deletions

**Entrypoints**:
- Web UI: https://radarr.<domain> (via Traefik)
- API: Port 7878 for automation and peer communication

**Network Configuration**:
- Connected to `smoonet` (static IP 172.18.0.10)
- Healthcheck: `/ping` endpoint via wget
- Media access: Mounts `/mnt/user/data` as `/data` for library interaction

### Sonarr
Sonarr handles series/TV show acquisition and library management:
- Monitors configured indexers (via Prowlarr) for series releases
- Interfaces with download clients to fetch episodes
- Renames, organizes, and moves completed downloads to Plex library folders
- Triggers library scans in Plex upon successful import
- Manages series metadata, upgrades, and deletions

**Entrypoints**:
- Web UI: https://sonarr.<domain> (via Traefik)
- API: Port 8989 (default, not overridden in compose) for automation

**Network Configuration**:
- Connected to `smoonet` (static IP inferred from similar services)
- Healthcheck: `/ping` endpoint
- Media access: Mounts `/mnt/user/data` as `/data` for library interaction

### Prowlarr
Prowlarr provides centralized indexer management:
- Aggregates and manages torrent and Usenet indexers
- Provides a unified API for Radarr and Sonarr to query indexers
- Handles indexer authentication, synchronization, and availability monitoring
- Eliminates redundant indexer configuration in child applications

**Entrypoints**:
- Web UI: https://prowlarr.<domain> (via Traefik)
- API: Port 9696 for Radarr/Sonarr integration

**Network Configuration**:
- Connected to `smoonet` (external network)
- No direct media access required; serves as middleware

## Inter-Stack Relationships

### Indexer Flow
1. Prowlarr maintains indexer configurations
2. Radarr and Sonarr query Prowlarr's API for indexer results
3. When a release is selected, Radarr/Sonarr send download commands to configured download clients (e.g., qBittorrent, Sabnzbd)
4. Download clients write to intermediate directories (typically `/mnt/user/data/downloads`)
5. Radarr/Sonarr monitor these directories for completed downloads
6. Upon completion, media files are moved/renamed to final library locations (`/mnt/user/data/Plex` or similar)
7. Radarr/Sonarr notify Plex to rescan updated library folders

### Media Server Integration
- Radarr and Sonarr both configure Plex as a media server connection
- Upon successful import, they trigger Plex library scans via Plex API
- Plex metadata agents enrich libraries with posters, summaries, etc.

## Network and Infrastructure Details

### Networks
- **br0**: MacVLAN providing direct LAN access with static IPs for services needing client accessibility (Plex)
- **smoonet**: Internal Docker network for inter-service communication (Radarr, Sonarr, Prowlarr, and Plex internal API)

### Storage Layout
- `/mnt/user/appdata/*`: Application configuration and databases
- `/mnt/user/data/Plex`: Primary media library (movies, shows)
- `/mnt/user/data/downloads`: Intermediate download directory (managed by external download clients)
- `/tmp/plex`: Plex transcode tmpfs volume (20GB)

### Health Monitoring
Each stack implements container healthchecks:
- Plex: `/identity` endpoint
- Radarr/Sonarr: `/ping` endpoint
- Prowlarr: Inherits healthcheck from base image (web UI responsiveness)

### Reverse Proxy Integration
All media stacks are exposed via Traefik with:
- Internal and external entrypoints differentiated by network
- Middleware chains for authentication and security
- Special bypass headers for privileged access
- Let's Encrypt TLS via websecure entrypoints

## Failure Modes and Resilience

### Dependency Failures
- If Prowlarr is unavailable, Radarr and Sonarr cannot search indexers (but may use cached results or fail configured indexer checks)
- If download clients are offline, media acquisition stalls but existing library remains available via Plex
- If Plex is unavailable, Radarr/Sonarr can still process downloads but cannot trigger library scans or update metadata

### Data Persistence
- All stacks store configuration in `/mnt/user/appdata` bind mounts
- Media library stored on persistent `/mnt/user/data` array
- Transcode tmpfs is ephemeral and safe to lose

### Recovery
- Stacks can be restarted independently
- Configuration backups implied via appdata persistence
- Plex database corruption requires manual recovery from appdata backups

## Operational Notes

### Version Tracking
- Images are pinned to specific versions with SHA256 hashes in compose files
- Updates require manual compose file modification and stack recreation

### Environment Specifics
- Timezone: Europe/Berlin
- User/group IDs: PUID=99, PGID=100 (consistent across media stacks)
- Umask: 022 (Radarr) ensuring group-readability of created files

### External Dependencies
This domain assumes presence of:
- Download clients (qBittorrent, Sabnzbd, etc.) configured in Radarr/Sonarr
- Functional DNS and network connectivity to indexer services
- Plex.tv account for remote access and claiming (Plex_CLAIM environment variable)

## Related Systems
- Traefik provides reverse proxy and TLS termination (see /openwiki/integrations/traefik-as-ingress.md)
- Komodo provides stack backup/restore integration (labels present in each stack)
- AutoKuma provides uptime monitoring (labels present in each stack)
- Tautulli provides Plex usage monitoring and triggers Radarr cleanup (see radarr scripts)
