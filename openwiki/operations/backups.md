---
type: concept
title: Backup Procedures
description: Describes backup strategies for stateful applications (Uptime Kuma, Cloudberry Backup) and configuration files (Traefik, Komodo) in the homelab stack.
tags: [backups, operations, stateful, configuration]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-bb59ae5ba473dc43d4ca3202
    resource: repo://stacks/traefik/scripts/cloudflare_trusted_ips/README.md
  - id: openwiki-source-41d817f9bb249436de417233
    resource: repo://stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---
# Backup Procedures

This document outlines backup procedures for stateful stacks and configuration files within the homelab environment. It covers automated and manual backup mechanisms, integration points with monitoring, and best practices for ensuring data integrity.

## Stateful Stack Backups

### Uptime Kuma
<!-- openwiki: broken internal link [../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md] file "../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md" does not exist. Fix the href or restore the target, then delete this comment. -->
Uptime Kuma's state (monitor configuration, history, and settings) is stored in its `appdata` directory. The [Unraid Appdata Backup Uptime Kuma Maintenance Helper](../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md) coordinates with the host's `appdata.backup` system to:
- Place Uptime Kuma monitors into maintenance mode before the backup begins (pre-run hook)
- Wait for Docker containers and related HTTP/DNS monitors to recover before exiting maintenance (post-run hook)
- Preserve existing maintenance ownership when possible
- Log operational details for auditability

This ensures that planned backup windows do not trigger false alerts in monitoring systems while guaranteeing the application's data is backed up consistently.

### Cloudberry Backup
As a GUI backup workflow container, Cloudberry Backup requires protection of its own configuration and operational data. While the stack does not include native backup automation, administrators should:
- Regularly back up the container's `appdata` directory (containing configuration, logs, and backup metadata)
- Ensure backup schedules do not conflict with active backup/restore operations
- Verify restore procedures for Cloudberry Backup's own configuration

<!-- openwiki: broken internal link [../stacks/cloudberry-backup/README.md] file "../stacks/cloudberry-backup/README.md" does not exist. Fix the href or restore the target, then delete this comment. -->
Refer to the [CloudBerry Backup stack documentation](../stacks/cloudberry-backup/README.md) for volume paths and container details.

## Configuration Backups

### Traefik
<!-- openwiki: broken internal link [../stacks/traefik/scripts/cloudflare_trusted_ips/README.md] file "../stacks/traefik/scripts/cloudflare_trusted_ips/README.md" does not exist. Fix the href or restore the target, then delete this comment. -->
Traefik's static (`traefik.yml`) and dynamic (`dynamic.yml`) configuration files are protected by the [Cloudflare Trusted IP Sync script](../stacks/traefik/scripts/cloudflare_trusted_ips/README.md), which:
1. Creates dated backups of both files under `/mnt/user/appdata/traefik/backups` before any modifications
2. Updates only the managed Cloudflare IP block in `traefik.yml`
3. Synchronizes related CrowdSec trusted IP settings in the Komodo-managed environment

This provides an automated rollback mechanism for configuration changes while maintaining security-related allowlists.

### Komodo
Komodo-managed secrets and configurations (including Traefik's runtime `.env` file) are version-controlled and encrypted in the `homelab-private` repository. The Cloudflare Trusted IP Sync script demonstrates the workflow:
- Local `.env` updates are encrypted via `sops`/`age`
- Encrypted artifacts (`.env.enc`) are committed alongside tracked templates (`.env.example`)
- Temporary clones ensure isolation during encryption and commit operations

This approach provides cryptographic backup of sensitive configuration while enabling GitOps workflows.

## Integration Points

### Monitoring Coordination
The Uptime Kuma maintenance helper exemplifies how backup procedures can integrate with observability systems to prevent alert fatigue during maintenance windows. Similar patterns can be applied to other stateful stacks.

### Configuration Versioning
Traefik's backup approach combined with Komodo's encrypted Git storage provides:
- Immediate rollback capability (local dated backups)
- Historical versioning (Git history)
- Cryptographic security (sops/age)
- Change auditability (Git commits)

## Best Practices
1. **Regular Validation**: Test restore procedures for both stateful data and configuration backups
2. **Separation of Concerns**: Keep backups isolated from primary storage (different physical media or cloud targets)
3. **Automation Leverage**: Use host-level backup systems (like Unraid's `appdata.backup`) where available
4. **Monitoring Awareness**: Coordinate with monitoring systems to suppress alerts during planned backup windows
5. **Encryption at Rest**: Ensure backups of sensitive data are encrypted (as demonstrated by Komodo/sops)
6. **Documentation**: Maintain clear runbooks for backup and restore procedures per stack

## Related Documentation
<!-- openwiki: broken internal link [../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md] file "../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Uptime Kuma Maintenance Helper](../stacks/uptime-kuma/scripts/appdata_backup_kuma_maintenance/README.md)
<!-- openwiki: broken internal link [../stacks/traefik/scripts/cloudflare_trusted_ips/README.md] file "../stacks/traefik/scripts/cloudflare_trusted_ips/README.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Cloudflare Trusted IP Sync (Traefik)](../stacks/traefik/scripts/cloudflare_trusted_ips/README.md)
<!-- openwiki: broken internal link [../workflows/deploy-stack.md] file "../workflows/deploy-stack.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Deploy Stack Workflow](../workflows/deploy-stack.md)
- [Update Secrets Workflow](../workflows/update-secrets.md)
- [Utility and Infrastructure Architecture](../architecture/utility-and-infrastructure.md)
