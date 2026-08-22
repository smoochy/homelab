# Stack Health

> Container liveness poller that alerts when a stack fails after a green deploy

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `stack-health`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

A deploy reporting success says nothing about the minutes after it. This stack polls every container of every stack through the Komodo read API, confirms anything that looks off against `docker inspect`, and alerts once a failure has survived three consecutive rounds.

It is deliberately not deployed by the deployment control plane it watches, but by the host's own Compose Manager, so recreating the deploy path cannot take the watcher down with it.

Its own liveness is covered from outside by an Uptime Kuma push monitor, which trips as soon as the poller stops completing rounds.

## Services

- `stack-health`

## Upstream

- Website: [https://komo.do/](https://komo.do/)
- GitHub: [https://github.com/moghtech/komodo](https://github.com/moghtech/komodo)

## Notes

- **This directory is the source of truth even though it deploys nothing.** The Compose Manager runs from its own copy under `/mnt/user/appdata/_composerize/stack-health/`, so a merged change here stays inert until it is carried over by hand, and a fix made only on the host is invisible to review and is reverted by the next hand-carried copy. Change this file first, carry it over afterwards, and `diff` the two before calling it done.
- **No `logging:` block, deliberately.** The container takes the host-wide default from `/etc/docker/daemon.json`, which ships its stdout to the log store. A block here would override that default and quietly keep this source out of the store. The log driver is fixed when a container is created, so a change to the daemon default reaches this stack only after `docker compose -p stack_health -f docker-compose.yml -f <override> up -d --force-recreate`.
- **The Compose Manager writes its own override.** `/boot/config/plugins/compose.manager/projects/stack-health/docker-compose.override.yml` carries the Unraid icon and WebUI labels, fed by that plugin's UI, and it wins over anything set here. The `docker-compose.override.yaml` tracked in this directory is an intentional no-op placeholder and is not that file.
