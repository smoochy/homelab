---
type: guide
title: Quickstart Guide
description: Guide new contributors to understand the homelab structure, navigate the OpenWiki, and get started with common tasks.
tags: [getting-started, navigation, overview]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-7b96bffe4d2727a9766a0d03
    resource: repo://stacks/traefik/.env.example
  - id: openwiki-source-84f2d5ff7cea82525de0d622
    resource: repo://stacks/traefik/compose.yaml
  - id: openwiki-source-63b6ca0f80e36f9622bd01f1
    resource: repo://stacks/traefik/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

# Quickstart Guide

This guide helps new contributors understand the homelab structure, navigate the OpenWiki documentation, and perform common tasks like deploying stacks, managing secrets, and configuring Traefik routes.

## Understanding the Homelab Structure

The homelab is organized into four primary domains, each with specific responsibilities:

| Domain | Responsibility | Key Services |
|--------|----------------|--------------|
| **[Edge and Networking](/openwiki/architecture/edge-and-networking.md)** | Secures perimeter, manages ingress, provides DNS filtering, monitors security threats | Traefik, Cloudflared, AdGuard Home, CrowdSec |
<!-- openwiki: broken internal link [/openwiki/architecture/identity-and-access.md] file "/openwiki/architecture/identity-and-access.md" does not exist. Fix the href or restore the target, then delete this comment. -->
| **[Identity and Access](/openwiki/architecture/identity-and-access.md)** | Manages authentication, authorization, deployment workflows, service dashboards | Komodo, Authentik, Homepage, Dozzle |
| **[Media](/openwiki/architecture/media.md)** | Automates media acquisition, organization, and streaming | Plex, Radarr, Sonarr, Prowlarr |
| **[Utility and Infrastructure](/openwiki/architecture/utility-and-infrastructure.md)** | Provides foundational services for monitoring, automation, communication, data persistence | Mosquitto, Registry, Uptime Kuma, Changedetection.IO, Cloudberry-Backup |

See the [Homelab Architecture Overview](/openwiki/architecture/overview.md) for detailed domain interactions and data flows.

## Navigating the OpenWiki

The OpenWiki documentation is organized by topic type:

- **Architecture** (`/openwiki/architecture/`): Domain overviews and system design
- **Concepts** (`/openwiki/concepts/`): Explanations of core technologies and workflows
- **Integrations** (`/openwiki/integrations/`): Planned service integrations
- **Operations** (`/openwiki/operations/`): Maintenance and operational procedures
- **Workflows** (`/openwiki/workflows/`): Step-by-step guides for common tasks

## Common Tasks

### Deploying a New Stack

To add a new service to the homelab:

1. Create a stack directory under `/stacks/` (e.g., `/stacks/myapp/`)
2. Add a `compose.yaml` defining your service
3. Create a tracked `.env.example` with configuration variables
4. Add stack-specific documentation in a `README.md`
5. Deploy via Komodo:
   - Access the Komodo UI at `https://komodo.example.com`
   - Click "Add Stack" and provide the Git repository URL
   - Configure deployment parameters (branch, compose file path)
   - Save and trigger deployment

<!-- openwiki: broken internal link [/openwiki/workflows/deploy-stack.md] file "/openwiki/workflows/deploy-stack.md" does not exist. Fix the href or restore the target, then delete this comment. -->
See the [Deploying a New Stack](/openwiki/workflows/deploy-stack.md) workflow for complete details.

### Managing Secrets with SOPS/Age

Secrets are encrypted in Git using SOPS and age:

1. Locate encrypted secrets (typically `.enc` files in stack directories)
2. Decrypt for editing:
   ```bash
   sops --decrypt <encrypted-file> > <decrypted-file>
   ```
3. Edit the decrypted file to update values
4. Re-encrypt:
   ```bash
   sops --encrypt <decrypted-file> > <encrypted-file>
   ```
5. Commit and push the encrypted file
6. Trigger redeployment in Komodo for the affected stack

See [Updating Secrets with SOPS/Age](/openwiki/workflows/update-secrets.md) for detailed procedures.

### Adding a Traefik Route

To expose a service via Traefik:

**Method 1 (Recommended): Define middleware in rules/, router/service via labels**

1. Create custom middleware (if needed) in `/stacks/traefik/rules/`
2. Add Traefik labels to your stack's `compose.yaml`:
   ```yaml
   labels:
     - "traefik.enable=true"
     - "traefik.http.routers.<service>.rule=Host(`<service>.example.com`)"
     - "traefik.http.routers.<service>.entrypoints=websecure-external"
     - "traefik.http.routers.<service>.tls=true"
     - "traefik.http.routers.<service>.middlewares=<middleware>@file,chain-external@file"
     - "traefik.http.services.<service>.loadbalancer.server.port=<port>"
   ```
3. Deploy/update the stack - Traefik will detect the new router automatically

**Method 2: Define everything statically in rules/**

Create a complete YAML file in `/stacks/traefik/rules/` with routers, services, and middlewares defined statically.

See [Adding a Traefik Route for a Stack](/openwiki/workflows/add-traefik-route.md) for complete instructions.

## Repository Layout

The layout is built to be easy to navigate:

<!-- openwiki: broken internal link [./stacks] file "./stacks" does not exist. Fix the href or restore the target, then delete this comment. -->
- [`stacks`](./stacks) contains the deployment files and local stack READMEs
- stack READMEs explain what each service is for, what images are used, and where the upstream project lives
