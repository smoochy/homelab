---
type: workflow
title: Komodo Deployment Workflow
description: Explains how Komodo functions as a deployment control plane, orchestrating stack deployments and managing secrets via SOPS/age through its core services (dockerproxy, mongo, core, periphery).
tags: ["komodo", "deployment", "control-plane", "sops", "age"]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-5ef0409c965921b60d6187d5
    resource: repo://stacks/komodo/compose.yaml
  - id: openwiki-source-71fa1bbc4a715e98914f8046
    resource: repo://stacks/komodo/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

Komodo operates as a self-hosted deployment control plane that manages the lifecycle of Docker-based stacks on a host. It provides an API and UI for deploying, updating, and monitoring stacks while handling secrets securely through SOPS and age encryption. The control plane consists of five core services working in conjunction: two Docker socket proxies (read-write and read-only), a MongoDB database for state persistence, the Komodo Core application for orchestration, and a specialized Periphery agent that executes deployment operations with built-in SOPS/age capabilities.

## Service Responsibilities

### dockerproxy and dockerproxy-ro
The `dockerproxy` service exposes the Docker socket with granular permissions required for stack management:
- `ALLOW_ARCHIVE=1` enables Compose to inject inline configuration files into containers
- `ALLOW_LOGS=1` permits log streaming for Komodo's UI and Dozzle integration
- `ALLOW_START/STOP/RESTART=1` provides container lifecycle control
- `ALLOW_BUILD=1` and `ALLOW_POST=1` support image building and pulling
- `ALLOW_CONTAINERS=1`, `ALLOW_IMAGES=1`, `ALLOW_NETWORKS=1`, `ALLOW_VOLUMES=1` enable resource inspection and management
- `ALLOW_SYSTEM=1` and `ALLOW_VERSION=1` allow daemon information queries
- `ALLOW_PING=1` provides health check capability
- `ALLOW_EVENTS=1` enables real-time container event monitoring

The read-only twin `dockerproxy-ro` mirrors these permissions except `POST=0`, preventing write operations while allowing observation consumers (like Traefik and Caddy service discovery) to remain unaffected during `dockerproxy` recreation.

### mongo
Persists Komodo's operational state including stack configurations, deployment history, user preferences, and encryption metadata. The database runs with minimal resource allocation (`--wiredTigerCacheSizeGB 0.25`) and stores data in named volumes for durability.

### core
Provides the primary user interface (web UI) and REST API for stack management. Core:
- Connects to MongoDB for state storage
- Uses `dockerproxy` (via `DOCKER_HOST=tcp://dockerproxy:2375`) to interact with the Docker daemon
- Manages stack definitions and triggers deployment workflows
- Communicates with Periphery through shared filesystem keys (`/config/keys`)
- Exposes endpoints on port 9120 for health checking (`/version`) and API operations

### periphery
Executes secure deployment operations using a custom image containing SOPS and age. Periphery:
- Connects to Docker via the same proxy (`DOCKER_HOST=tcp://dockerproxy:2375`)
- Decrypts SOPS-encrypted secrets using age private keys stored in `/config/keys`
- Clones stack repositories to `/etc/komodo/repos`
- Builds and deploys stacks to `/etc/komodo/stacks` using build outputs in `/etc/komodo/builds`
- Mounts host directories for script execution and cross-container file access
- Performs health checks via HTTPS self-signed certificate on port 8120 (`/version` endpoint)

## Deployment Workflow

When a user initiates a stack deployment through Komodo's UI or API:

1. **Configuration Storage**: Core validates and stores the stack definition in MongoDB, including repository URL, branch, compose file path, and deployment parameters.

2. **Trigger Periphery**: Core signals Periphery to begin deployment by writing a trigger file to the shared repository directory or via internal messaging (implementation detail).

3. **Repository Sync**: Periphery pulls the latest commits from the stack's Git repository into `/etc/komodo/repos`.

4. **Secret Decryption**: For any SOPS-encrypted files found in the repository, Periphery uses the age private key from `/config/keys` to decrypt secrets in-memory, never writing decrypted secrets to disk.

5. **Stack Rendering**: Periphery processes the stack's compose files, substituting decrypted secrets where required (e.g., environment variables, file contents).

6. **Deployment Execution**: Periphery uses the Docker proxy to:
   - Pull required container images
   - Create or update Docker networks, volumes, and secrets
   - Deploy the stack as a Docker Compose project
   - Apply labels (including `komodo.skip=true` to prevent interference with host-wide stop operations)

7. **Status Reporting**: Periphery reports deployment success or failure back to Core via shared filesystem state, which updates the stack's status in MongoDB and the UI.

## Secrets Management via SOPS/age

Komodo's Periphery image includes SOPS and age tooling specifically for managing secrets in GitOps workflows:
- Secrets are encrypted in repositories using `sops --encrypt --age <public-key>` 
- The corresponding age private key is stored securely on the host in `/mnt/user/appdata/komodo/config/keys` and mounted into both Core and Periphery containers
- During deployment, Periphery decrypts secrets only in memory using the private key
- Decrypted values are passed directly to Docker containers via environment options or file mounts, avoiding persistent storage of plaintext secrets
- This enables Git-safe secret storage while maintaining secure runtime handling

## Networking and Integration

All services communicate over the user-defined `smoonet` bridge network (172.18.128.0/17 subnet), which Komodo creates automatically on first deployment. Core and Periphery Traefik labels enable secure external access via configured domains, with internal service discovery facilitated by the shared network.

The control plane design deliberately avoids overriding Docker's default logging configuration, ensuring all container outputs flow to the host's centralized logging system via `/etc/docker/daemon.json`.

## Failure Modes and Resilience

- **Proxy Unavailability**: If `dockerproxy` is unhealthy, Core and Periphery cannot interact with the Docker daemon, halting deployments until proxy recovery
- **Database Loss**: MongoDB persistence prevents state loss; backups are configured via `/backups` volume mount
- **Key Compromise**: Exposure of age private keys would allow decryption of repository secrets; keys should be protected with host-level encryption and strict filesystem permissions
- **Network Partition**: Loss of `smoonet` connectivity isolates services; the network is designed as a single-host bridge for local communication only

## Operational Considerations

- Stack deployments require the Periphery image (`ghcr.io/smoochy/komodo-periphery-sops-age`) which bundles SOPS and age
- The `komodo.skip=true` label on all services prevents Komodo's internal `StopAllContainers` action from affecting its own operation
- Periphery requires access to host directories for script execution (e.g., `/mnt/user/appdata/qbittorrent/scripts`) to support stack-specific automation
- Upgrades follow the official Komodo v2 migration guide when moving from v1 deployments
