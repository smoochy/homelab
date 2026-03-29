# Radarr

> Movie acquisition and library management stack

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `radarr`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `radarr`

## Upstream

- Website: [https://radarr.video/](https://radarr.video/)
- GitHub: [https://github.com/Radarr/Radarr](https://github.com/Radarr/Radarr)

## Scripts

- [Auto Tag and Deferred Cleanup for Watched Movies](./scripts/auto_tag/README.md): Tautulli-driven watched-state handling and deferred Radarr cleanup for movie files.
