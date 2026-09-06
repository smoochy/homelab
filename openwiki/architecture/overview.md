---
type: concept
title: Homelab Architecture Overview
description: Provides a high-level overview of the homelab architecture, including the main domains (edge/networking, identity/access, media, utility) and their interactions.
tags: [architecture, overview, homelab]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-71fa1bbc4a715e98914f8046
    resource: repo://stacks/komodo/README.md
  - id: openwiki-source-63b6ca0f80e36f9622bd01f1
    resource: repo://stacks/traefik/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

# Homelab Architecture Overview

This document provides a high-level overview of the homelab architecture, organized into four primary domains: edge and networking, identity and access, media, and utility and infrastructure. Each domain contains interconnected stacks that work together to provide a cohesive self-hosted environment.

## Domains and Responsibilities

### Edge and Networking
The edge and networking domain secures the perimeter, manages ingress, provides DNS filtering, and monitors security threats. Key responsibilities include:
- Terminating TLS and routing HTTP(S) traffic via Traefik
- Establishing secure tunnels to Cloudflare (optional) via Cloudflared
- Providing network-wide ad blocking and recursive DNS resolution via AdGuard Home with Unbound
- Analyzing logs, detecting threats, and enforcing bans via CrowdSec
See [Edge and Networking Domain](/openwiki/architecture/edge-and-networking.md) for detailed documentation.

### Identity and Access
The identity and access domain manages authentication, authorization, deployment workflows, and service dashboards. Key responsibilities include:
- Providing centralized identity management and authentication via Authentik (OIDC, SAML, LDAP)
- Orchestrating stack deployments and managing encrypted secrets via Komodo (with SOPS/age integration)
- Offering a unified dashboard for service discovery and quick links via Homepage
- Enabling real-time container log viewing and troubleshooting via Dozzle
These components work together to secure access to services and simplify operational workflows.

### Media
The media domain automates media acquisition, organization, and streaming. Key responsibilities include:
- Streaming and managing media libraries via Plex (with hardware acceleration and remote access)
- Automating movie discovery, download, and library organization via Radarr
- Automating series/TV show discovery, download, and library organization via Sonarr
- Centralizing indexer management for Radarr and Sonarr via Prowlarr
See [Media Domain](/openwiki/architecture/media.md) for detailed documentation.

### Utility and Infrastructure
The utility and infrastructure domain provides foundational services for monitoring, automation, communication, and data persistence. Key responsibilities include:
- Enabling IoT device communication via MQTT broker (Mosquitto)
- Hosting private Docker images for internal use via Registry
- Tracking internet speed performance and alerting on degradation via Speedtest-Tracker
- Bridging smart home devices to Apple HomeKit via Homebridge
- Monitoring website changes and triggering notifications via Changedetection.IO
- Managing backups for critical application data via Cloudberry-Backup
- Visualizing service uptime and response times via Uptime Kuma
- Sending notifications to multiple platforms (Discord, Telegram, email, etc.) via Apprise

## Inter-Domain Interactions

### Traffic Flow and Access
1. External requests enter via Cloudflare (if using Cloudflared tunnels) or directly to the homelab's public IP.
2. Traffic reaches Traefik (edge domain), which performs TLS termination, applies middleware (including CrowdSec security bouncers), and routes requests to appropriate services.
3. Services in the identity domain (Authentik, Komodo, Homepage, Dozzle) are protected by Traefik middleware, requiring authentication for access.
4. Media services (Plex, Radarr, Sonarr, Prowlarr) are accessed via Traefik, with Plex additionally bound to the br0 MacVLAN for direct LAN client access.
5. Utility services are typically accessed internally or via Traefik for web interfaces (e.g., Uptime Kuma, Changedetection.IO).

### Authentication and Authorization
- Authentik (identity domain) serves as the central identity provider, issuing tokens for Traefik forward-auth middleware.
- Traefik (edge domain) validates tokens with Authentik before forwarding requests to protected services in media, identity, and utility domains.
- Komodo (identity domain) uses Authentik for admin console access and may generate service-specific credentials for stack deployments.

### Deployment and Configuration
- Komero (identity domain) orchestrates deployments of stacks across all domains using Docker Compose.
- Komodo reads encrypted secrets (managed via SOPS/age) and injects them into stacks at deploy time.
- Traefik (edge domain) dynamically discovers services via Docker provider (through a read-only socket proxy) and updates routes based on stack labels.
- Media stacks (Radarr, Sonarr) communicate with Prowlarr (media domain) for indexer queries and with download clients (often in utility domain, e.g., Sabnzbd) for acquisitions.
- Utility services like Mosquitto receive messages from various stacks (e.g., Homebridge for smart home events, Changedetection.IO for change alerts).

### Data and Storage
- Media libraries are stored on persistent storage (`/mnt/user/data`) and accessed by Plex (media domain) and utility services like Cloudberry-Backup (for backups).
- Application configurations and databases are stored in `/mnt/user/appdata` bind mounts for each stack.
- Transcoding buffers (e.g., Plex's tmpfs volume) are ephemeral and domain-specific.
- Monitoring utility (Uptime Kuma) collects health metrics from services across all domains via HTTP checks or agents.

### Security and Observability
- CrowdSec (edge domain) analyzes logs from Traefik, Authentik, Komodo, and other services to detect threats and distribute bans.
- Traefik applies CrowdSec bouncer middleware to edge-facing routers (external chains) while leaving internal chains (e.g., for dashboard access) unbouncered.
- Dozzle (identity domain) provides log viewing for troubleshooting services in any domain.
- Uptime Kuma (utility domain) monitors service availability and triggers notifications via Apprise on failures.

## Network Segmentation
The homelab uses two primary Docker networks:
- **br0**: A MacVLAN network providing direct LAN access with static IPs for services requiring client accessibility (primarily Plex in the media domain for direct device streaming).
- **smoonet**: An internal Docker network for inter-service communication (used by most stacks in identity, media, and utility domains for API communication and internal requests).

Traefik connects to both networks, enabling it to route traffic appropriately based on entrypoint configuration (internal vs. external).

## Operational Workflow
1. Stack deployment is initiated via Komodo (identity domain), which pulls encrypted secrets, renders environment templates, and executes `docker compose up`.
2. Traefik (edge domain) detects new services via Docker provider and updates routing configuration.
3. Services register with Authentik (identity domain) for single sign-on or with Homepage for dashboard links.
4. Media acquisition workflows begin with Prowlarr querying indexers, triggering downloads via utility domain clients (e.g., Sabnzbd), and post-processing via Radarr/Sonarr.
5. Monitoring stacks (Uptime Kuma, Changedetection.IO) continuously observe service health and data changes, issuing alerts via Apprise.
6. Security monitoring (CrowdSec) runs continuously, analyzing logs and updating bouncers in Traefik and firewall layers.

This modular domain structure allows independent evolution of each area while maintaining clear integration points through Traefik, Authentik, Komodo, and shared storage/networking.
