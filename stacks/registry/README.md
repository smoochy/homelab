# Docker Registry

> Container registry stack with a lightweight registry UI

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `registry`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `registry`
- `registry-ui`

## Upstream

### `registry`

- Website: [https://distribution.github.io/distribution/](https://distribution.github.io/distribution/)
- GitHub: [https://github.com/distribution/distribution](https://github.com/distribution/distribution)

### `registry-ui`

- Website: [https://github.com/Quiq/docker-registry-ui](https://github.com/Quiq/docker-registry-ui)
- GitHub: [https://github.com/Quiq/docker-registry-ui](https://github.com/Quiq/docker-registry-ui)
