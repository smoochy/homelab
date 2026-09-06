---
type: concept
title: Utility and Infrastructure Domain
description: Documentation of utility and infrastructure stacks providing messaging (Mosquitto), container storage (Registry), monitoring (Uptime Kuma), and backup (CloudBerry Backup) services for the homelab.
tags: [utility, infrastructure, mosquitto, registry, uptime-kuma, cloudberry-backup]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-6926178d1d7b1c4bea4d5467
    resource: repo://stacks/mosquitto/compose.yaml
  - id: openwiki-source-2b6be43029be3ad539e720a1
    resource: repo://stacks/mosquitto/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

# Utility and Infrastructure Domain

This domain encompasses foundational services that support the operation, monitoring, and maintenance of the homelab environment. These stacks provide essential capabilities including lightweight messaging, container image storage, service uptime monitoring, and backup/restore operations.

Mosquitto provides MQTT broker functionality for lightweight publish/subscribe messaging in the homelab, with health monitored by the stack-health poller due to lack of native HTTP health endpoints.

## Mosquitto

### Role
The Mosquitto stack provides an MQTT broker for lightweight publish/subscribe messaging between services and devices. It enables event-driven communication with minimal overhead, suitable for IoT devices, sensors, and internal service coordination.

### Services
- `mosquitto`: The Eclipse Mosquitto broker instance

### Key Characteristics
- Exposes standard MQTT ports: 1883 (TCP), 8883 (TLS), and 9001 (WebSocket)
- Configured for Unraid deployment with specific PUID/PGID mapping (99:100)
- Integrates with Uptime Kuma for health monitoring via AutoKuma labels
- No HTTP health endpoint; liveness is monitored by the stack-health poller
- Persists configuration to `/mnt/user/appdata/mosquitto:/config:rw`

### Communication Patterns
Services connect to the broker using MQTT protocol to publish messages to topics or subscribe to receive messages. The broker handles message distribution, quality of service levels, and retained messages.

## Docker Registry

### Role
The Docker Registry stack provides a private container image registry with a lightweight web UI for managing and distributing container images across the homelab environment.

### Services
- `registry`: The distribution registry service implementing the Docker Registry HTTP API v2
- `registry-ui`: A web interface (Quiq/docker-registry-ui) for browsing and managing images

### Key Characteristics
- Registry service pulls from `distribution/distribution` upstream
- Registry UI provides visual interface for image repository management
- Both services share the `smoonet` network for internal communication
- Configured for Unraid with standard PUID/PGID mapping
- Enables internal image storage and distribution without reliance on external registries

### Usage Pattern
Services build and push container images to the private registry for deployment across the homelab. The registry UI allows operators to inspect available images, tags, and digest information.

## Uptime Kuma

### Role
Uptime Kuma provides self-hosted monitoring service with a status dashboard for tracking the availability and performance of internal services and external endpoints.

### Services
- `uptime-kuma`: The monitoring application instance

### Key Characteristics
- Exposes web interface on port 3001 (implicit from standard configuration)
- Includes maintenance helper scripts for coordinating with Unraid backup windows
- Implements AutoKuma labels for self-monitoring of its own Docker container
- Stores monitoring data and configuration in `/mnt/user/appdata/uptime-kuma:/app/data`
- Provides HTTP endpoints for health checks and metric collection

### Monitoring Capabilities
Supports various monitor types including HTTP(s), TCP, Ping, DNS, and Steam game servers. Features include uptime calculations, response time tracking, SSL certificate expiration monitoring, and customizable alerting mechanisms.

## CloudBerry Backup

### Role
CloudBerry Backup provides a GUI-driven backup and restore solution for protecting data across the homelab environment, supporting both local and cloud storage destinations.

### Services
- `cloudberry-backup`: The MSP360 (CloudBerry) Backup containerized application

### Key Characteristics
- Exposes web interface on port 5800 and VNC on port 5900 for GUI access
- Includes healthcheck mechanism that probes the web GUI root path
- Integrates with Unraid backup systems through hook scripts for icon permissions
- Maps backup storage to `/mnt/user/backups:/storage:ro` and configuration to `/mnt/user/appdata/CloudBerryBackup:/config:rw`
- Configured for European timezone (Europe/Berlin) with specific niceness and UMASK settings

### Backup Functionality
Provides file-level backup, encryption, compression, scheduling, and retention policies. Supports multiple storage destinations including local disks, network shares, and cloud providers through its GUI interface.

## Inter-Service Relationships

While each stack operates independently, they form interconnected infrastructure layers:
- **Messaging**: Mosquitto enables event-driven communication between monitoring, backup, and other services
- **Storage**: Registry stores container images that may include monitoring agents or backup utilities
- **Monitoring**: Uptime Kuma tracks health of Mosquitto, Registry, CloudBerry Backup, and other services
- **Data Protection**: CloudBerry Backup protects critical data including Uptime Kuma monitoring data and Registry image metadata

These utility services collectively provide the foundational operational capabilities that allow higher-level application stacks to function reliably within the homelab environment.
