# Episeerr

> Episode automation stack for rule-based media request and cleanup workflows

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `episeerr`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `episeerr`

## Upstream

- Website: [https://github.com/Vansmak/episeerr](https://github.com/Vansmak/episeerr)
- GitHub: [https://github.com/Vansmak/episeerr](https://github.com/Vansmak/episeerr)

## Network Notes

Use direct internal service addressing on `smoonet` for service-to-service traffic.

- Preferred internal URL: `http://episeerr:5002`
- Tautulli webhook target on the same Docker network: `http://episeerr:5002/webhook`
- Preferred direct Tautulli URL from `episeerr`: `http://tautulli:8181`
