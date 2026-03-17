# Authentik

> Identity, SSO, and access management for internal services

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `authentik`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../docs/sops-age-komodo.md).

## Services

- `postgresql`
- `server`
- `worker`

## Upstream

### `postgresql`

- Website: [https://www.postgresql.org/](https://www.postgresql.org/)
- GitHub: [https://github.com/postgres/postgres](https://github.com/postgres/postgres)

### `server`

- Website: [https://goauthentik.io/](https://goauthentik.io/)
- GitHub: [https://github.com/goauthentik/authentik](https://github.com/goauthentik/authentik)

### `worker`

- Website: [https://goauthentik.io/](https://goauthentik.io/)
- GitHub: [https://github.com/goauthentik/authentik](https://github.com/goauthentik/authentik)

## Notes

- This stack is not yet in active use in the current homelab deployment.
- The full configuration and integration with [`traefik`](../traefik/README.md) is planned for the coming weeks.
