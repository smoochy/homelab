# Tracearr

> Media server monitoring and tracing stack for actionable observability

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `tracearr`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `tracearr`

## Network Notes

Use direct internal service addressing on `smoonet` for service-to-service traffic.

- Preferred internal URL: `http://tracearr:3000`
- Preferred direct Plex URL after dual-networking Plex: `http://plex:32400`

## Data Persistence

Tracearr stores runtime state under `/mnt/user/appdata/tracearr` so the daily appdata backup captures the database and cache state.

- PostgreSQL data: `/mnt/user/appdata/tracearr/postgres` -> `/data/postgres`
- Redis data: `/mnt/user/appdata/tracearr/redis` -> `/data/redis`
- Tracearr backup path: `/mnt/user/appdata/tracearr/backup` -> `/data/backup`

Stop the container before restoring these directories to avoid partial database writes. Migration snapshots from the initial move are stored under `/mnt/user/appdata/tracearr/migration-backups`.

## Upstream

- Website: [https://tracearr.com/](https://tracearr.com/)
- GitHub: [https://github.com/connorgallopo/tracearr](https://github.com/connorgallopo/tracearr)
