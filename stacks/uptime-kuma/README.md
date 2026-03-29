# Uptime Kuma

> Uptime monitoring and status dashboard for internal services

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `uptime-kuma`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `uptime-kuma`

## Upstream

- Website: [https://uptimekuma.org/](https://uptimekuma.org/)
- GitHub: [https://github.com/louislam/uptime-kuma](https://github.com/louislam/uptime-kuma)

## Scripts

- [Appdata Backup Uptime Kuma Maintenance Helper](./scripts/appdata_backup_kuma_maintenance/README.md): Host-side helper that wraps Unraid appdata backup windows in dedicated Uptime Kuma maintenance handling.
