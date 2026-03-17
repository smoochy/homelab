# Caddy

> Reverse proxy stack for external routing, TLS, and edge entrypoints

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `caddy`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../docs/sops-age-komodo.md).

## Services

- `caddy`

## Upstream

- Website: [https://caddyserver.com/](https://caddyserver.com/)
- GitHub: [https://github.com/caddyserver/caddy](https://github.com/caddyserver/caddy)

## Related Links

- Custom Caddy modules image: [https://github.com/smoochy/caddy-modules](https://github.com/smoochy/caddy-modules)

## Notes

- Use `Caddyfile.example` as the base for the local runtime Caddy configuration.
- The Cloudflare-enabled image used here is built from the companion `caddy-modules` repository.
- The active reverse proxy in this homelab is currently [`traefik`](../traefik/README.md), so this `caddy` stack is not being configured and used as the primary edge service right now.
