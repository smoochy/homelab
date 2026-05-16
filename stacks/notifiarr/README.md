# Notifiarr

> Notification and automation integration stack for the broader media toolchain

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `notifiarr`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `notifiarr`

## Upstream

- Website: [https://notifiarr.com/](https://notifiarr.com/)
- GitHub: [https://github.com/golift/notifiarr](https://github.com/golift/notifiarr)

## Network Notes

Use direct internal service addressing on `smoonet` for service-to-service traffic.

- Preferred internal URL: `http://notifiarr:5454`
- Do not route internal callers through Traefik for this service.
