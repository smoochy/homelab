---
type: Domain
title: Access & Control
description: Komodo deployment control plane, Authentik identity provider, Homepage dashboard, Dozzle log viewer — access management and operational visibility
tags: [domain, access, control, komodo, authentik, homepage, dozzle]
resource: https://github.com/smoochy/homelab/tree/main/stacks
openwiki:
  roles: [domain, architecture]
  change_kinds: [deployment, identity, observability]
  source_paths: [stacks/komodo/, stacks/authentik/, stacks/homepage/, stacks/dozzle/]
  symbols: [compose.yaml, .env.example, KOMODO_*, PERIPHERY_*, AUTHENTIK_*, HOMEPAGE_*, DOZZLE_*]
  test_paths: []
  invariants: [Komodo creates smoonet network, Periphery image includes sops+age, Authentik is the OIDC provider, Homepage aggregates service links, Dozzle reads Docker socket via proxy]
  validation_commands: [docker compose -f stacks/komodo/compose.yaml config, docker compose -f stacks/authentik/compose.yaml config]
---

# Access & Control

This domain covers the **control plane**, **identity**, **dashboards**, and **log visibility** for the homelab.

## Stack Overview

| Stack | Role | Key Files |
|-------|------|-----------|
| `komodo` | Deployment control plane (Core + MongoDB + Periphery w/ SOPS+age + Docker Proxy) | `compose.yaml`, `.env.example` |
| `authentik` | Identity provider (OIDC, SAML, LDAP, passwordless) | `compose.yaml`, `.env.example` |
| `homepage` | Customizable service dashboard | `compose.yaml`, `.env.example`, service config YAML |
| `dozzle` | Log viewer for Docker containers | `compose.yaml`, `.env.example` |

---

## Komodo Stack (`stacks/komodo/`)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Komodo Core                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   MongoDB   │  │   Core API  │  │   Web UI / Webhooks │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                    gRPC + mTLS (passkey)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Komodo Periphery                          │
│  ┌─────────────────────┐  ┌─────────────────────────────┐  │
│  │  Stack Execution    │  │  SOPS + age (preinstalled)  │  │
│  │  (docker compose)   │  │  Decrypt .env.enc → .env    │  │
│  └─────────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                    Docker Socket Proxy
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Docker Host                             │
│  Stacks: traefik, radarr, sonarr, sabnzbd, ...             │
└─────────────────────────────────────────────────────────────┘
```

### Services

| Service | Image | Purpose |
|---------|-------|---------|
| `core` | `ghcr.io/moghtech/komodo:2` | API, UI, scheduling, webhooks, MongoDB client |
| `mongo` | `mongo:7` | Persistent storage for stacks, servers, procedures, users |
| `periphery` | `ghcr.io/smoochy/komodo-periphery-sops-age:2` | Stack execution, SOPS/age decryption, terminal access |
| `dockerproxy` | `ghcr.io/linuxserver/docker-socket-proxy` | Secure Docker socket access (read-only by default) |

### Key Invariants

| Invariant | Description |
|-----------|-------------|
| **Network creator** | `komodo/compose.yaml` creates `smoonet` bridge network on first deploy (`external: false`) |
| **Periphery image** | Uses `ghcr.io/smoochy/komodo-periphery-sops-age` — SOPS and age preinstalled for `.env.enc` decryption |
| **Passkey auth** | Core ↔ Periphery authenticate via `KOMODO_PASSKEY` (shared secret) |
| **Pre Deploy pattern** | Every stack resource uses `sops -d .env.enc > .env` in Komodo Pre Deploy |
| **Webhook flow** | GitHub → Cloudflared (optional) → Komodo Core webhook → checkout update → Pre Deploy → redeploy |
| **Backup path** | `COMPOSE_KOMODO_BACKUPS_PATH=/mnt/user/appdata/komodo/backups` for dated MongoDB dumps |

### Critical Environment Variables

#### Core (`KOMODO_*`)
```env
KOMODO_HOST=https://komodo.example.com          # Public URL (OAuth, webhooks, Caddy)
KOMODO_FIRST_SERVER=https://komodo-periphery:8120  # Periphery gRPC endpoint
KOMODO_PASSKEY=                                  # Shared secret for Core↔Periphery
KOMODO_WEBHOOK_SECRET=                           # GitHub webhook validation
KOMODO_JWT_SECRET=                               # JWT signing
KOMODO_DB_USERNAME= / KOMODO_DB_PASSWORD=        # MongoDB auth
KOMODO_LOCAL_AUTH=true                           # Username/password login
KOMODO_INIT_ADMIN_USERNAME= / KOMODO_INIT_ADMIN_PASSWORD=  # Initial admin
KOMODO_DISABLE_USER_REGISTRATION=true            # No public signup
KOMODO_DISABLE_NON_ADMIN_CREATE=true             # Only admins create resources
```

#### Periphery (`PERIPHERY_*`)
```env
PERIPHERY_ROOT_DIRECTORY=/etc/komodo             # Stack working directories
PERIPHERY_PASSKEYS=                              # Must include KOMODO_PASSKEY
PERIPHERY_SSL_ENABLED=true                       # Self-signed certs for gRPC
PERIPHERY_CORE_PUBLIC_KEYS=                      # Core public key for verification
PERIPHERY_INCLUDE_DISK_MOUNTS=/etc/hostname      # Disk size reporting fix
```

### Deployment Workflow

1. **Initial deploy**: `docker compose -f stacks/komodo/compose.yaml up -d`
   - Creates `smoonet` network
   - Initializes MongoDB
   - Core starts, generates keys
   - Periphery connects to Core via `KOMODO_FIRST_SERVER`

2. **Configure in UI**:
   - Set `KOMODO_PERIPHERY_PUBLIC_KEYS` in Core env (from Periphery logs)
   - Create first admin user
   - Add stacks as Resources (Run Directory: `stacks/<name>`, Config Files: `.env.enc`)

3. **Stack deployment via Komodo**:
   - Push to repo → GitHub webhook → Komodo
   - Komodo updates checkout on host
   - Pre Deploy: `sops -d .env.enc > .env`
   - `docker compose up -d` in stack directory

### Unraid-Specific Notes

- **Absolute repo paths**: Use `KOMODO_REPO_NAME` for single-file bind mounts:
  ```yaml
  /mnt/user/appdata/komodo/repos/${KOMODO_REPO_NAME:-homelab}/stacks/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
  ```
- **Periphery on Unraid**: Runs in Docker (not systemd), so `KOMODO_FIRST_SERVER=https://komodo-periphery:8120`
- **Backups**: `COMPOSE_KOMODO_BACKUPS_PATH` on cache/appdata for MongoDB dumps

### Migration: Komodo v1 → v2

Follow official guide: <https://komo.do/docs/releases/v2.0.0#upgrading-to-komodo-v2>

Key changes:
- Core + Periphery architecture (v1 was single binary)
- Passkey-based auth
- MongoDB required
- New resource model

---

## Authentik Stack (`stacks/authentik/`)

### Role
**Identity Provider** for the homelab — OIDC, SAML, LDAP, passwordless, MFA.

### Services
- **authentik** — Combined worker + server (or split `authentik-worker` + `authentik-server`)
- **postgresql** — Database (or external)
- **redis** — Cache/task queue

### Key Configuration
```env
AUTHENTIK_SECRET_KEY=                          # Django secret
AUTHENTIK_POSTGRES_PASSWORD=                   # DB password
AUTHENTIK_REDIS_PASSWORD=                      # Redis password
AUTHENTIK_EMAIL_HOST= / AUTHENTIK_EMAIL_PORT=  # SMTP for verification
AUTHENTIK_ERROR_REPORTING_ENABLED=false        # Disable Sentry
```

### Integration Points
- **Komodo OIDC**: `KOMODO_OIDC_ENABLED=true`, `KOMODO_OIDC_PROVIDER=https://auth.example.com/application/o/komodo`
- **Homepage**: OIDC login via Authentik
- **Traefik**: ForwardAuth middleware (optional, not currently used — CrowdSec plugin handles edge)
- **Other services**: *arr apps, Plex, etc. can use Authentik as OIDC provider

### Blueprints
Authentik supports "blueprints" for declarative provider/application setup. Consider exporting configuration as blueprints for reproducibility.

---

## Homepage Stack (`stacks/homepage/`)

### Role
**Customizable dashboard** aggregating service links, status widgets, and info cards.

### Services
- **homepage** — Static site (Go template + YAML config), served via Docker

### Configuration
- `docker compose` mounts `config/` directory with:
  - `settings.yaml` — Theme, layout, authentication
  - `services.yaml` — Service groups, links, icons, status widgets
  - `widgets.yaml` — Kubernetes, Docker, API widgets
  - `custom.css` / `custom.js` — Styling/behavior overrides

### Key Features Used
- **Docker widget**: Container status for stacks on `smoonet`
- **OIDC authentication**: Via Authentik (optional)
- **Service icons**: From `https://homepage-icons.vercel.app/` or local
- **Unraid WebGUI links**: `<STACK>_UNRAID_WEBGUI_URL` from each stack's env

### Example Service Entry (from `services.yaml`)
```yaml
- Media:
    - Radarr:
        href: https://radarr.example.com
        icon: radarr.png
        widget:
          type: docker
          container: radarr
```

---

## Dozzle Stack (`stacks/dozzle/`)

### Role
**Real-time log viewer** for Docker containers — lightweight alternative to `docker logs -f`.

### Services
- **dozzle** — Web UI reading Docker socket via proxy

### Configuration
```env
DOZZLE_LEVEL=info                              # Default log level
DOZZLE_FILTER=                                 # Global label filter
DOZZLE_TAIL=300                                # Lines to show on load
DOZZLE_ADDRESS=:8080                           # Listen port
```

### Access
- Exposed via Traefik: `dozzle.example.com`
- Middleware: `chain-internal` (no CrowdSec, internal access only)
- Reads Docker socket via `dockerproxy` (from `komodo` stack) — no direct socket mount

### Integration
- **Komodo**: Dozzle container labeled for Traefik discovery
- **Homepage**: Link to Dozzle with Docker widget showing container status

---

## Cross-Stack Relationships

```mermaid
flowchart LR
    subgraph ControlPlane[Control Plane]
        KomodoCore[Komodo Core]
        KomodoPeriphery[Komodo Periphery\n(sops+age)]
        MongoDB[(MongoDB)]
        DockerProxy[Docker Socket Proxy]
    end

    subgraph Identity[Identity]
        Authentik[Authentik\n(OIDC/SAML/LDAP)]
        PostgreSQL[(PostgreSQL)]
        Redis[(Redis)]
    end

    subgraph Observability[Observability]
        Homepage[Homepage\nDashboard]
        Dozzle[Dozzle\nLog Viewer]
    end

    subgraph Edge[Edge]
        Traefik[Traefik\nIngress]
    end

    KomodoCore --> MongoDB
    KomodoCore --> KomodoPeriphery
    KomodoPeriphery --> DockerProxy
    DockerProxy --> DockerHost[(Docker Host)]
    
    Authentik --> PostgreSQL
    Authentik --> Redis
    
    KomodoCore -.->|OIDC| Authentik
    Homepage -.->|OIDC| Authentik
    Homepage -->|Docker widget| DockerProxy
    Dozzle -->|Docker socket| DockerProxy
    
    Traefik -->|Routes| KomodoCore
    Traefik -->|Routes| Authentik
    Traefik -->|Routes| Homepage
    Traefik -->|Routes| Dozzle
```

---

## Validation

```bash
# Validate Komodo compose
docker compose -f stacks/komodo/compose.yaml config

# Validate Authentik compose
docker compose -f stacks/authentik/compose.yaml config

# Validate Homepage compose
docker compose -f stacks/homepage/compose.yaml config

# Validate Dozzle compose
docker compose -f stacks/dozzle/compose.yaml config

# Check Komodo Core health
curl -f https://komodo.example.com/health

# Check Authentik health
curl -f https://auth.example.com/api/v3/health/

# Check Homepage
curl -f https://homepage.example.com/

# Check Dozzle
curl -f https://dozzle.example.com/healthz
```

---

## Related Pages

- [Stacks Overview](../architecture/stacks-overview.md) — Stack model and conventions
- [Edge & Networking](./edge-networking.md) — Traefik ingress routing for these services
<!-- openwiki: broken internal link [../workflows/encrypted-deployment.md] file "../workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Encrypted Deployment](../workflows/encrypted-deployment.md) — SOPS/age/Komodo workflow
<!-- openwiki: broken internal link [./media-automation.md] file "./media-automation.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Media Automation](./media-automation.md) — *Arr stacks deployed via Komodo