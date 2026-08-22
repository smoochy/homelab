# Komodo

> Self-hosted deployment control plane with a custom Periphery image that includes SOPS and age

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `komodo`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `dockerproxy`
- `dockerproxy-ro`
- `mongo`
- `core`
- `periphery`

## Upstream

### `dockerproxy`

- Website: [https://docs.linuxserver.io/images/docker-socket-proxy/](https://docs.linuxserver.io/images/docker-socket-proxy/)
- GitHub: [https://github.com/linuxserver/docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy)

### `dockerproxy-ro`

- Website: [https://komo.do/](https://komo.do/)
- GitHub: [https://github.com/moghtech/komodo](https://github.com/moghtech/komodo)

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

- **No service here declares `logging:`, deliberately.** All five take the host-wide default from `/etc/docker/daemon.json`, which ships every container's stdout to the log store. A `logging:` block in this file would override that default for the container it sits on and quietly keep that source out of the store. The log driver is fixed when a container is created, so a change to the daemon default reaches this stack only after `docker compose -p komodo -f docker-compose.yml -f <override> up -d --force-recreate`, which recreates `dockerproxy` too.
- `compose.yaml` intentionally manages the first creation of the shared `smoonet` bridge network so a fresh host can deploy Komodo without a manual `docker network create smoonet` step. Later redeploys reuse the same named network.
- The deployed Periphery image is based on `ghcr.io/smoochy/komodo-periphery-sops-age` so SOPS and age are available inside the Komodo host workflow.
- If you are migrating an existing Komodo v1 deployment to v2, follow the official upgrade guide: <https://komo.do/docs/releases/v2.0.0#upgrading-to-komodo-v2>.
- The encryption and decrypt flow is documented in [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).
