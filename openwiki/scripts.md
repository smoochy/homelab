---
type: Reference
title: Operational Scripts
description: Helper scripts bundled with certain stacks for maintenance and automation.
tags: [scripts, automation, maintenance]
---

# Operational Scripts

Some stacks in the repository include focused helper scripts under `stacks/<stack>/scripts/`. These scripts cover small operational workflows such as post-processing, state handling, queue cleanup, and maintenance automation that are tied to a concrete service stack.

## Where to Find Scripts

Look inside a stack's directory for a `scripts/` subdirectory. Each script typically has its own folder with a `README.md` explaining its purpose and usage.

## Examples

### Radarr
- **Auto Tag and Deferred Cleanup for Watched Movies**:  
  `stacks/radarr/scripts/auto_tag/README.md`

### SABnzbd + Gluetun
- **Download Speed Monitor and Recovery Script**:  
  `stacks/sabnzbd/scripts/monitor_sab_speed/README.md`
- **ISO Extractor Post-Processing Script**:  
  `stacks/sabnzbd/scripts/extract_iso/README.md`
- **Delete Items From History Scripts**:  
  `stacks/sabnzbd/scripts/delete_item_from_history/README.md`

### Uptime Kuma
- **Appdata Backup Uptime Kuma Maintenance Helper**:  
  `stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md`

## Writing a Stack-Specific Script

If you want to add a maintenance script for a stack:

1. Create a directory under `stacks/<stack>/scripts/<script-name>/`.
2. Add the script(s) and a `README.md` that explains:
   - What the script does.
   - How to run it.
   - Any dependencies or configuration needed.
3. Ensure the script is well-documented and tested (if applicable).

## Source

- Script locations: `/stacks/*/scripts/`
- Example script READMEs: See the links above.