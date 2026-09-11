# Komodo

> Self-hosted deployment control plane with a custom Periphery image that includes SOPS and age

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `komodo`.

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

- **No service here declares `logging:`, deliberately.** All five take the host-wide default from `/etc/docker/daemon.json`, which ships every container's stdout to the log store. A `logging:` block in this file would override that default for the container it sits on and quietly keep that source out of the store. The log driver is fixed when a container is created, so a change to the daemon default reaches this stack only after the `--force-recreate` carry-over in the stack-recovery runbook, which recreates `dockerproxy` too.
- **This stack is not deployed by Komodo, and merging a change to it does not deploy anything.** Komodo cannot redeploy the stack it runs in, so this one is deployed by Unraid's Compose Manager from its own copy of the compose file and `.env` under `/mnt/user/appdata/_composerize/komodo/`. That copy drifts from this directory silently: a merged fix stays inert until it is carried over by hand. Copy `compose.yaml` onto the host copy, add any `.env` key the host copy is missing, and bring the stack up with both files. The invocation, the file selection and the traps around it live in the stack-recovery runbook and are deliberately not repeated here.
- **This directory is the source of truth even though it deploys nothing.** Because the host copy is what actually runs, it is tempting to fix a problem there and stop. Do not: an edit that lives only on the host is invisible to review, to the public export and to anyone reading this repository, and the next hand-carried copy of `compose.yaml` silently reverts it. Every change to this stack is made here first and carried to the host afterwards. A change made on the host under time pressure is not finished until the same change is committed here and the two files are byte-identical again - `diff` them before calling it done.
- **`dockerproxy-ro` is the proxy every non-Komodo consumer reads through.** It grants only `CONTAINERS`, `NETWORKS`, `EVENTS`, `INFO`, `PING`, `VERSION` and `ALLOW_LOGS`, with `POST=0`, so every endpoint it can reach is a read. Traefik, Caddy, Homepage and Dozzle point at it, which is what keeps service discovery alive when `dockerproxy` is recreated. Three consumers stay on `dockerproxy` because they write: `crowdsec-manager` (`POST /containers/<id>/exec`), `traefik-manager` (`RESTART_METHOD=proxy`) and `authentik-worker` (Outpost containers). The `:ro` on the socket mount does not make either proxy read-only - `POST=0` does.
- **`DOCKER_HOST` beats Traefik's own `endpoint:`.** Traefik builds its Docker client from the environment, so `DOCKER_HOST` in `stacks/traefik/compose.yaml` wins over `providers.docker.endpoint` in `traefik.yml`. Measured on 2026-08-19: after `traefik.yml` was pointed at `dockerproxy-ro` and the container restarted, Traefik still held its connection to `dockerproxy`. Moving Traefik therefore needs a recreate with the new environment, not a restart - both places are kept in sync anyway so the difference cannot bite twice.
- **`ALLOW_LOGS` on `dockerproxy` is load-bearing for Komodo itself, not only for Dozzle.** Periphery has no socket mount and runs `docker logs` against `DOCKER_HOST`, so a `GetContainerLog` call arrives at the proxy as `GET /containers/<id>/logs`. Removing the grant would break Komodo's own log view. Verified live on 2026-08-19 by issuing `GetContainerLog` over the API and watching the request appear in the proxy's access log from Periphery's address.
- **Recreating `dockerproxy` interrupts whatever Komodo is doing.** Both `core` and `periphery` reach Docker only through this proxy, so restarting or recreating it during a deploy aborts the compose run in flight and can leave a stack with its containers removed and never recreated. Check that no update is running before touching it, and recover an affected stack with a deploy rather than a restart: `docker compose restart` restarts existing containers and creates none.
- **Container icons and WebUI links do not come from `compose.yaml`.** Unraid's Compose Manager writes its own `docker-compose.override.yml` under `/boot/config/plugins/compose.manager/projects/komodo/`, fed by the icon and WebUI fields of its UI, and its `net.unraid.docker.icon` and `net.unraid.docker.webui` labels win over anything the compose file sets. An icon corrected here can therefore never take effect - change it in that override file, then recreate the containers with the carry-over invocation in the stack-recovery runbook. Both files ship a `.bak` copy next to them before any hand edit.
- **`core` mounts Periphery's repository clone read-only.** `/mnt/user/appdata/komodo/repos` is Periphery's working copy, but the `trigger_procedure` action runs in Core's own Deno runtime, and it diffs each stack's last deployed commit against the pulled one, over that stack's compose and env files, to decide which stacks a push actually changed. Only those files, because a stack directory also holds a README and host helper scripts that no container ever sees - and that narrowing holds only as long as no `compose.yaml` here mounts a relative path. Without that mount every push sweeps all ~29 stacks and pays a blind grace period for each no-op, which is roughly three minutes. Core only ever reads it - the clone stays Periphery's. The action tolerates the mount being absent and falls back to sweeping everything, so the two can be rolled out in either order. See the update-stacks-action runbook.
- `compose.yaml` intentionally manages the first creation of the shared `smoonet` bridge network so a fresh host can deploy Komodo without a manual `docker network create smoonet` step. Later redeploys reuse the same named network.
- The deployed Periphery image is based on `ghcr.io/smoochy/komodo-periphery-sops-age` so SOPS and age are available inside the Komodo host workflow.
- If you are migrating an existing Komodo v1 deployment to v2, follow the official upgrade guide: <https://komo.do/docs/releases/v2.0.0#upgrading-to-komodo-v2>.
