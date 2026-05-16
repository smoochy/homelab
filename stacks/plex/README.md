# Plex

> Media server stack for library streaming and remote access

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `plex`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `plex`

## Upstream

- Website: [https://www.plex.tv/](https://www.plex.tv/)
- GitHub: [https://github.com/linuxserver/docker-plex](https://github.com/linuxserver/docker-plex)

## Network Notes

`plex` is expected to run on both `br0` and `smoonet`.

- `br0` keeps the fixed LAN address for Plex client traffic.
- `smoonet` provides internal Docker reachability for Traefik and other stacks such as `tracearr`.
