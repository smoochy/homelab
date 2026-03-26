# Komodo

> Self-hosted deployment control plane with a custom Periphery image that includes SOPS and age

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `komodo`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `dockerproxy`
- `mongo`
- `core`
- `periphery`

## Upstream

### `dockerproxy`

- Website: [https://docs.linuxserver.io/images/docker-socket-proxy/](https://docs.linuxserver.io/images/docker-socket-proxy/)
- GitHub: [https://github.com/linuxserver/docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy)

### `mongo`

- Website: [https://www.mongodb.com/](https://www.mongodb.com/)
- GitHub: [https://github.com/mongodb/mongo](https://github.com/mongodb/mongo)

### `core`

- Website: [https://komo.do/](https://komo.do/)
- GitHub: [https://github.com/moghtech/komodo](https://github.com/moghtech/komodo)

### `periphery`

- Website: [https://komo.do/](https://komo.do/)
- GitHub: [https://github.com/smoochy/komodo-periphery-sops-age](https://github.com/smoochy/komodo-periphery-sops-age)

## Related Links

- Periphery image with SOPS + age: [https://github.com/smoochy/komodo-periphery-sops-age](https://github.com/smoochy/komodo-periphery-sops-age)

## Notes

- The deployed Periphery image is based on `ghcr.io/smoochy/komodo-periphery-sops-age` so SOPS and age are available inside the Komodo host workflow.
- If you are migrating an existing Komodo v1 deployment to v2, follow the official upgrade guide: <https://komo.do/docs/releases/v2.0.0#upgrading-to-komodo-v2>.
- The encryption and decrypt flow is documented in [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).
