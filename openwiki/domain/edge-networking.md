---
type: Domain
title: Edge & Networking
description: Traefik ingress, Cloudflared tunnel, AdGuard Home + Unbound DNS, CrowdSec LAPI — edge routing, security, and DNS for the homelab
tags: [domain, edge, networking, traefik, cloudflared, adguard, crowdsec, dns]
resource: https://github.com/smoochy/homelab/tree/main/stacks
openwiki:
  roles: [domain, architecture]
  change_kinds: [networking, security, dns]
  source_paths: [stacks/traefik/, stacks/cloudflared/, stacks/adguard-home-unbound/, stacks/crowdsec/]
  symbols: [traefik.yml, dynamic.yml, compose.yaml, CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS]
  test_paths: []
  invariants: [Traefik is the sole ingress, CrowdSec plugin applies only to external chains, Cloudflared is optional for webhook exposure, AdGuard uses Unbound as recursive resolver]
  validation_commands: [docker compose -f stacks/traefik/compose.yaml config, docker compose -f stacks/adguard-home-unbound/compose.yaml config]
---

# Edge & Networking

This domain covers the **network edge**: ingress routing, TLS termination, edge security (CrowdSec), public tunnel access, and DNS filtering/resolution.

## Stack Overview

| Stack | Role | Key Files |
|-------|------|-----------|
| `traefik` | Core ingress, routing, CrowdSec plugin, geoipupdate, Traefik Manager, log dashboard | `compose.yaml`, `traefik.yml`, `dynamic.yml`, `.env.example` |
| `cloudflared` | Optional Cloudflare Tunnel for public Komodo webhook endpoint | `compose.yaml`, `.env.example`, tunnel config |
| `adguard-home-unbound` | DNS filtering (AdGuard) + recursive resolver (Unbound) | `compose.yaml`, `.env.example` |
| `crowdsec` | LAPI for CrowdSec bouncer (referenced by Traefik plugin) | `compose.yaml`, `.env.example` |

---

## Traefik Stack (`stacks/traefik/`)

### Services
- **traefik** — Reverse proxy, load balancer, TLS termination
- **geoipupdate** — MaxMind GeoIP database updates for CrowdSec geoip enrichment
- **traefik-manager** — Web UI for route/middleware/service/cert management
- **traefik-log-dashboard** — Log visualization dashboard
- **traefik-log-dashboard-agent** — Log shipper for the dashboard

### Configuration Model

```
traefik.yml          → Static config: entrypoints, providers (file: dynamic.yml), experimental plugins
dynamic.yml          → Dynamic config: middlewares, routers, services, TLS options
.env / .env.enc      → Runtime secrets: API tokens, CrowdSec keys, domain names
scripts/cloudflare_trusted_ips/ → Host-side sync of Cloudflare IP ranges → CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS
```

### Key Invariants

| Invariant | Description |
|-----------|-------------|
| **File provider only** | `traefik.yml` loads `dynamic.yml` via file provider; no HTTP provider endpoint enabled |
| **CrowdSec plugin** | Registered in `traefik.yml` as experimental plugin `github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin` |
| **Middleware injection** | `crowdsec-bouncer` middleware defined via Docker labels on `traefik` service; LAPI key from `.env` |
| **Chain scoping** | `crowdsec-bouncer@docker` applied only on `chain-external` and `chain-external-bypass` in `dynamic.yml` |
| **Internal chains clean** | `chain-internal` and `chain-internal-bypass` intentionally stay CrowdSec-free |
| **Trusted IPs alignment** | `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` must match `websecure-external.forwardedHeaders.trustedIPs` in `dynamic.yml` |

### Cloudflare Trusted IP Sync Script

**Location**: `stacks/traefik/scripts/cloudflare_trusted_ips/`

Host-side automation that:
1. Fetches current Cloudflare IP ranges
2. Updates `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` in `stacks/traefik/.env.enc` and `.env.example`
3. Creates dated backups of `traefik.yml` and `dynamic.yml` under `/mnt/user/appdata/traefik/backups/`
4. Runs on schedule (cron/Unraid User Scripts)

<!-- openwiki: broken internal link [./integrations/cloudflare-trusted-ip-sync.md] file "./integrations/cloudflare-trusted-ip-sync.md" does not exist. Fix the href or restore the target, then delete this comment. -->
See script [README](./integrations/cloudflare-trusted-ip-sync.md) for details.

### Traefik Manager

Web UI at `TRAEFIK_MANAGER_EXTERNAL_URL` for:
- Route, middleware, service, certificate management
- Log viewing
- Static configuration inspection

### Log Dashboard

- **traefik-log-dashboard** at `TRAEFIK_LOG_DASHBOARD_EXTERNAL_URL`
- **traefik-log-dashboard-agent** ships logs from Traefik to dashboard

---

## Cloudflared Stack (`stacks/cloudflared/`)

### Purpose
Provides a **public HTTPS endpoint** for Komodo webhook reception without opening inbound ports on the host.

### When to Use
- Komodo runs on a host without public IP / port forwarding
- GitHub webhooks need to reach Komodo
- Prefer Cloudflare Tunnel over direct exposure

### Configuration
- Tunnel credentials stored in `.env.enc` (via SOPS/age)
- Tunnel config maps hostname → `komodo-core` internal port
- Runs as a sidecar or standalone stack

### Integration
- GitHub webhook URL → `https://<tunnel-hostname>/webhook`
- Komodo `KOMODO_WEBHOOK_SECRET` validates payloads

---

## AdGuard Home + Unbound (`stacks/adguard-home-unbound/`)

### Architecture
```
Client → AdGuard Home (filtering, blocklists) → Unbound (recursive resolution) → Authoritative DNS
```

### Services
- **adguard-home** — DNS filtering, blocklists, DHCP, DoH/DoT
- **unbound** — Recursive resolver, DNSSEC validation, caching

### Key Configuration
- AdGuard upstream → `unbound:53` (internal)
- Unbound root hints, root key, cache settings
- Blocklists: OISD, HaGeZi, custom
- Client access: LAN subnets, optional VPN

### Unraid Notes
- Use host network or dedicated bridge
- Persist Unbound cache/keys to appdata

---

## CrowdSec LAPI (`stacks/crowdsec/`)

### Role
Runs the **CrowdSec Local API (LAPI)** that the Traefik plugin's bouncer queries for decisions.

### Services
- **crowdsec** — LAPI + agent (parses logs, pushes decisions)
- **crowdsec-db** — PostgreSQL for LAPI (if not using SQLite)

### Integration with Traefik
1. Traefik plugin registers bouncer with LAPI (via `CROWDSEC_TRAEFIK_BOUNCER_API_KEY`)
2. On each request to `chain-external`, plugin queries LAPI
3. LAPI returns decision (allow/ban/captcha) based on scenarios, IP reputation
4. Traefik enforces decision via middleware

### Configuration
- `CROWDSEC_TRAEFIK_BOUNCER_API_KEY` in `.env.enc` (generated via `cscli bouncers add`)
- Scenarios: HTTP probing, brute force, custom
- Parsers: Traefik access log format (via `traefik` collection)

---

## Deployment Notes

### Traefik as Sole Ingress
All external traffic enters via Traefik. Other stacks expose services through Traefik labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`service.example.com`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.middlewares=chain-external@file"
```

### Network
All stacks join `smoonet` (created by `komodo` stack). Traefik connects to service containers via Docker service names.

### TLS
- Traefik terminates TLS (Let's Encrypt via ACME or Cloudflare DNS challenge)
- Certificates stored in `traefik` volume (`/letsencrypt`)
- Internal communication: HTTP (no mTLS currently)

### Unraid Host Paths
For single-file bind mounts from repo, use absolute paths with `KOMODO_REPO_NAME`:
```yaml
/mnt/user/appdata/komodo/repos/${KOMODO_REPO_NAME:-homelab}/stacks/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro
```

---

## Validation

```bash
# Validate Traefik compose
docker compose -f stacks/traefik/compose.yaml config

# Validate AdGuard+Unbound compose
docker compose -f stacks/adguard-home-unbound/compose.yaml config

# Check Traefik static config syntax
docker run --rm -v $(pwd)/stacks/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
  traefik:v3.0 traefik validate --configFile=/etc/traefik/traefik.yml

# Test CrowdSec bouncer registration
docker exec crowdsec cscli bouncers list
```

---

## Related Pages

- [Stacks Overview](../architecture/stacks-overview.md) — Stack model and conventions
- [Access & Control](./access-control.md) — Komodo, Authentik, Homepage, Dozzle
<!-- openwiki: broken internal link [../workflows/encrypted-deployment.md] file "../workflows/encrypted-deployment.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Encrypted Deployment](../workflows/encrypted-deployment.md) — SOPS/age/Komodo workflow for `.env.enc`
<!-- openwiki: broken internal link [./integrations/cloudflare-trusted-ip-sync.md] file "./integrations/cloudflare-trusted-ip-sync.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Cloudflare Trusted IP Sync](./integrations/cloudflare-trusted-ip-sync.md) — Host-side IP range automation