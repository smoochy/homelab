---
type: concept
title: Traefik as Ingress for Internal Services
description: Documents how Traefik exposes internal services (media stacks, utility stacks) via internal and external entrypoints, applying middleware chains and handling TLS termination.
tags: [traefik, ingress, routing, middleware, tls]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-d05539273d4d5a06fdb00d0f
    resource: repo://stacks/radarr/compose.yaml
  - id: openwiki-source-63b6ca0f80e36f9622bd01f1
    resource: repo://stacks/traefik/README.md
  - id: openwiki-source-6dce58a1cec766ad46edecc4
    resource: repo://stacks/traefik/traefik.yml
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

## Overview

Traefik serves as the central ingress controller for the homelab, responsible for routing traffic to internal services, applying security and transformation middleware, and terminating TLS connections. Services are exposed through Traefik using Docker labels that define routers, middlewares, and services. The configuration splits traffic between internal and external networks, applying different middleware chains based on the entrypoint.

## Entrypoints

Traefik configures multiple entrypoints for handling traffic:
- `websecure-internal`: Used for HTTPS services accessed from within the homelab network (e.g., via internal DNS or direct IP). Listens on port 443.
- `websecure-external`: Used for HTTPS services accessed from outside the homelab (typically via Cloudflare or direct public DNS). Listens on port 444.
- `web-internal`: HTTP entrypoint for internal traffic that redirects to `websecure-internal`. Listens on port 80.
- `web-external`: HTTP entrypoint for external traffic that redirects to `websecure-external`. Listens on port 81.

Both HTTPS entrypoints are defined in Traefik's static configuration (`traefik.yml`). TLS is terminated at Traefik, meaning backend services receive unencrypted HTTP traffic.

## Middleware Chains

Middleware chains are defined in the Traefik rules directory (`rules/base.yml`) and applied to routers based on the entrypoint and traffic type. The chains combine multiple middleware functions:

- `chain-internal`: Applied to internal traffic. Includes:
  - `security-headers`: Sets security-related HTTP headers (HSTS, frame denial, etc.).
  - `gzip`: Enables response compression.

- `chain-internal-bypass`: Similar to `chain-internal` but used for specific bypass scenarios (e.g., health checks or internal tooling that should skip certain checks). Includes:
  - `security-headers`
  - `gzip`

- `chain-external`: Applied to external traffic. Includes:
  - `security-headers`: Same security headers as internal.
  - `crowdsec-bouncer`: Integrates with CrowdSec for IP blocking and threat prevention.
  - `gzip`: Response compression.

- `chain-external-bypass`: Similar to `chain-external` but used for services requiring external access without CrowdSec (e.g., certain integrations or internal tools exposed externally). Includes:
  - `security-headers`
  - `crowdsec-bouncer`
  - `gzip`

The `traefik-warp` plugin was previously used but removed due to performance issues; client IP preservation is now handled statically via `forwardedHeaders.trustedIPs` on the entrypoint and the CrowdSec bouncer's own configuration.

## Service Discovery

Services are discovered via Docker labels applied in each service's `compose.yaml`. Traefik's Docker provider (configured to use a read-only socket proxy) reads these labels to dynamically create routers, middlewares, and services. Key labels include:

- `traefik.enable=true`: Enables Traefik for the service.
- Router labels (e.g., `traefik.http.routers.<SERVICE>-internal.rule`): Define the hostname rule (`Host(\`${TRAEFIK_EXTERNAL_URL}\`)`) and associate the router with an entrypoint (`websecure-internal` or `websecure-external`), priority, middleware chain, and TLS setting.
- Service labels (e.g., `traefik.http.services.<SERVICE>.loadbalancer.server.url`): Point to the service's internal address (e.g., `http://127.0.0.1:7878` for Radarr).

The `${SERVICE}` variable is typically set to the service name (e.g., `radarr`), and `${TRAEFIK_EXTERNAL_URL}` and `${TRAEFIK_INTERNAL_URL}` are defined in the stack's `.env` file.

## TLS Termination

TLS certificates are managed externally (e.g., via Let's Encrypt or manually imported) and loaded into Traefik. Traefik terminates TLS at the ingress point, decrypting traffic before applying middleware and forwarding to backend services as plain HTTP. This simplifies service configuration, as backend services do not need to handle TLS directly.

Certificates are stored in Traefik's `acme.json` file (for Let's Encrypt) or defined via static file providers. The `tls: true` label on routers indicates that Traefik should use the default certificate store for the given hostname.

## Example: Radarr and Sonarr

Both Radarr and Sonarr follow the same pattern in their `compose.yaml` files:

```yaml
labels:
  - traefik.enable=true
  # Internal router
  - traefik.http.routers.${SERVICE}-internal.entrypoints=websecure-internal
  - traefik.http.routers.${SERVICE}-internal.middlewares=chain-internal@file
  - traefik.http.routers.${SERVICE}-internal.priority=5000
  - traefik.http.routers.${SERVICE}-internal.rule=Host(`${TRAEFIK_EXTERNAL_URL}`)
  - traefik.http.routers.${SERVICE}-internal.service=${SERVICE}
  - traefik.http.routers.${SERVICE}-internal.tls=true
  # External router
  - traefik.http.routers.${SERVICE}-external.entrypoints=websecure-external
  - traefik.http.routers.${SERVICE}-external.middlewares=chain-external@file
  - traefik.http.routers.${SERVICE}-external.priority=10
  - traefik.http.routers.${SERVICE}-external.rule=Host(`${TRAEFIK_EXTERNAL_URL}`)
  - traefik.http.routers.${SERVICE}-external.service=${SERVICE}
  - traefik.http.routers.${SERVICE}-external.tls=true
  # Bypass router (for special headers)
  - traefik.http.routers.${SERVICE}-bypass.entrypoints=websecure-external
  - traefik.http.routers.${SERVICE}-bypass.middlewares=chain-external-bypass@file
  - traefik.http.routers.${SERVICE}-bypass.priority=2500
  - traefik.http.routers.${SERVICE}-bypass.rule=Host(`${TRAEFIK_EXTERNAL_URL}`) && Header(`${SPECIAL_HEADER_NAME}`, `${SPECIAL_HEADER_SECRET}`)
  - traefik.http.routers.${SERVICE}-bypass.service=${SERVICE}
  - traefik.http.routers.${SERVICE}-bypass.tls=true
  # Traefik-specific settings
  - traefik.docker.network=smoonet
  - traefik.http.services.${SERVICE}.loadbalancer.server.url=${TRAEFIK_INTERNAL_URL}
```

This configuration creates three routers per service:
- Internal: For LAN access with internal middleware chain.
- External: For WAN access with external middleware chain (including CrowdSec).
- Bypass: For external access requiring a special header (e.g., for certain integrations or admin tools), applying the external bypass chain.

The service itself points to an internal URL (e.g., `http://radarr:7878` via `${TRAEFIK_INTERNAL_URL}`), which Traefik resolves using the Docker network (`smoonet`).

## Configuration Location

- Static Traefik configuration (entrypoints, providers, etc.): `stacks/traefik/traefik.yml`
- Dynamic middleware chains and router/service definitions (file-based): `stacks/traefik/rules/`
- Per-service Traefik labels: Defined in each stack's `compose.yaml` (e.g., `stacks/radarr/compose.yaml`)
- Environment variables (including `${TRAEFIK_EXTERNAL_URL}`): Defined in `stacks/<stack>/.env.example` and loaded via `.env`

## Related Documentation

- For adding new routes, see the workflow: [Add Traefik Route](/openwiki/workflows/add-traefik-route.md)
- For network architecture: [Edge and Networking](/openwiki/architecture/edge-and-networking.md)
- For media stack details: [Media Architecture](/openwiki/architecture/media.md)
- For utility stacks: [Utility and Infrastructure Architecture](/openwiki/architecture/utility-and-infrastructure.md)
