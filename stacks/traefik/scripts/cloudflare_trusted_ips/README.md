# Cloudflare Trusted IP Sync

This host-side automation refreshes the managed Cloudflare trusted IP block in
Traefik and keeps the CrowdSec forwarded-header allowlist in sync with it.

It is intended for Unraid or similar Docker hosts where:

- `/mnt/user/appdata/traefik/traefik.yml` is the live Traefik config file
- `/mnt/user/appdata/traefik/dynamic.yml` is the companion dynamic config file
- `/mnt/user/appdata/komodo/repos/homelab-private/stacks/traefik/.env` is the
  local runtime env file that Komodo may overwrite from Git on later pulls
- `komodo-periphery` already has `sops` and `age` available

## Files

- `cloudflare_trusted_ips.py`: cross-platform implementation
- `cloudflare_trusted_ips.sh`: POSIX launcher for Unraid, Linux, and macOS
- `cloudflare_trusted_ips.ps1`: PowerShell launcher for Windows
- `.env.example`: host configuration template

Only the script files and `.env.example` are committed. The real `.env` stays
local on the host.

## What It Does

1. Creates dated backups of `/mnt/user/appdata/traefik/traefik.yml` and
   `/mnt/user/appdata/traefik/dynamic.yml` under
   `/mnt/user/appdata/traefik/backups`.
2. Downloads the current Cloudflare IPv4 and IPv6 ranges.
3. Replaces only the managed block inside `/mnt/user/appdata/traefik/traefik.yml`.
4. Updates `CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS` in the local Traefik runtime
   env file under the Komodo repo checkout.
5. Creates a fresh temporary clone of `homelab-private`.
6. Renders the tracked `stacks/traefik/.env.example` inside that temporary clone
   from the already-updated local Traefik runtime `.env`.
7. Calls `sops` and `age` from inside `komodo-periphery` to write the updated
   `stacks/traefik/.env.enc` into that temporary clone.
8. Commits and pushes `stacks/traefik/.env.enc` together with
   `stacks/traefik/.env.example` to `main` when the local Traefik runtime `.env`
   changed and the repo-tracked env artifacts differ from the current `main`
   branch state.
9. Deletes the temporary clone before exit, even on failure.

The script never commits, stages, or pushes inside
`/mnt/user/appdata/komodo/repos/homelab-private`.

## Requirements

- Host access to `git`, `docker`, and either `uv` or `python3`
- Network access to:
  - `https://www.cloudflare.com/ips-v4`
  - `https://www.cloudflare.com/ips-v6`
- SSH push access to `git@github.com:smoochy/homelab-private.git`
- A running `komodo-periphery` container with:
  - `sops`
  - `age-keygen`
  - the age identity at `/root/.config/sops/age/keys.txt`
- The temporary repo base path must be reachable inside `komodo-periphery`
  through the `/root` bind mount. The default `/mnt/user/appdata/komodo/root/tmp`
  satisfies that requirement.

## Install

### 1. Copy the script folder to the host

Place the folder in a persistent host path, for example:

```text
/mnt/user/appdata/traefik/scripts/cloudflare_trusted_ips
```

### 2. Create the local `.env`

Use `.env.example` as the template and create:

```text
/mnt/user/appdata/traefik/scripts/cloudflare_trusted_ips/.env
```

Adjust the paths only if your host differs from the defaults.

### 3. Make the POSIX launcher executable

```sh
chmod +x /mnt/user/appdata/traefik/scripts/cloudflare_trusted_ips/cloudflare_trusted_ips.sh
```

### 4. Schedule it

Example Unraid User Scripts entry:

```bash
#!/bin/bash
bash /mnt/user/appdata/traefik/scripts/cloudflare_trusted_ips/cloudflare_trusted_ips.sh
```

Do not execute the launcher directly from `/boot/...` on Unraid. The flash drive
mount often behaves as non-executable storage, which results in `Permission denied`.
Keep the real script folder under `/mnt/user/appdata/...` and call it through
`bash` from the User Scripts plugin.

## Notes

- Every run creates two dated backup files in `/mnt/user/appdata/traefik/backups`,
  even when the Cloudflare list did not change and the run ends as a no-op.
- The backup files are plain file snapshots of the host-side `traefik.yml` and
  `dynamic.yml` state before the script makes any changes in that run.
- To restore a previous version, copy the chosen backup file back over the live
  Traefik file on the host and then redeploy or restart Traefik through your
  normal operations workflow.
- There is currently no automatic backup retention or cleanup.
- The local runtime `.env` is intentionally updated before the temporary clone
  and push step. If the later Git step fails, the next successful run will reuse
  that already-updated local value.
- If `/mnt/user/appdata/komodo/repos/homelab-private/stacks/traefik/.env` does
  not change in a run, the script skips the temporary clone, Git commit, and
  GitHub push entirely.
- The pushed repo artifacts for a successful sync are `stacks/traefik/.env.enc`
  and `stacks/traefik/.env.example`.
- The script prints timestamped plain log lines with blank-line-separated sections
  so Unraid User Scripts output stays readable without ANSI color handling.
