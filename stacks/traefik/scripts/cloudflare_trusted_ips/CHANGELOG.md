# Changelog

## 2026-03-29

### Initial release

- First repository release of `cloudflare_trusted_ips` as a host-side helper
  for keeping the managed Cloudflare trusted IP block in Traefik aligned with
  the CrowdSec forwarded-header allowlist.
- Added:
  - `cloudflare_trusted_ips.py`
  - `cloudflare_trusted_ips.sh`
  - `cloudflare_trusted_ips.ps1`
  - `.env.example`
  - `README.md`
  - `CHANGELOG.md`
- Added dated pre-change backups for the live host `traefik.yml` and
  `dynamic.yml` files under `/mnt/user/appdata/traefik/backups`.
- Added structured runtime logging for validation, backup creation,
  Cloudflare fetches, file updates, Git sync, cleanup, and final status.
- Added local runtime `.env` updates for
  `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` in the Komodo checkout used by the
  Traefik stack.
- Added temporary-repo encryption flow through `komodo-periphery` so the host
  can regenerate and push `stacks/traefik/.env.enc` without committing from
  the live Komodo checkout.
- Added tracked `stacks/traefik/.env.example` rendering from the updated
  Traefik runtime `.env` so the public export can immediately reflect the new
  trusted IP list.
- Added isolated public-preview automation for the Traefik env-sync path so
  the technical preview PR is still created in `homelab-private`, but the
  matching public `homelab` sync is published automatically without affecting
  the general manual preview flow.
