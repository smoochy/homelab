# Stack Health

> Container liveness poller that alerts when a stack fails after a green deploy

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `stack-health`.

A deploy reporting success says nothing about the minutes after it. This stack polls every container of every stack through the Komodo read API, confirms anything that looks off against `docker inspect`, and alerts once a failure has survived three consecutive rounds. A container left in `created` is the one exception and alerts on the first round it is seen in, because that state is never one a container is passing through by the time the stack is looked at.

It also polls Komodo's Repo resources and alerts when a repo's last clone or pull failed. That verdict cannot be subscribed to: Komodo has no alert variant for a failed `PullRepo` and a Repo resource has no failure-alert flag, so an `on_pull` hook that exits non-zero is rendered red and announced nowhere. The same three-round debounce, six-hourly reminder and recovery message apply.

It is deliberately not deployed by the deployment control plane it watches, but by the host's own Compose Manager, so recreating the deploy path cannot take the watcher down with it.

Its own liveness is covered from outside by an Uptime Kuma push monitor, which trips as soon as the poller stops completing rounds.

## Services

- `stack-health`

## Upstream

- Website: [https://komo.do/](https://komo.do/)
- GitHub: [https://github.com/moghtech/komodo](https://github.com/moghtech/komodo)

## Notes

- **A stack Komodo is deploying is skipped, but not forever.** The deploy window is every in-flight update plus `STACK_HEALTH_DEPLOY_GRACE_SECONDS` after each completed one, counted from that update's `start_ts`, so a stack redeployed more often than the grace window would never be looked at again - which is how a container left in `created` by one deploy stayed invisible in #2579. `STACK_HEALTH_MAX_BUSY_SKIPS` bounds it: after that many consecutive skips the stack is checked while still busy. Ten by default, twice the grace window, so no single deploy reaches it.
- **This directory is the source of truth even though it deploys nothing.** The Compose Manager runs from its own copy under `/mnt/user/appdata/_composerize/stack-health/`, so a merged change here stays inert until it is carried over by hand, and a fix made only on the host is invisible to review and is reverted by the next hand-carried copy. Change this file first, carry it over afterwards, and `diff` the two before calling it done. The invocation and its traps live in the stack-recovery runbook and are deliberately not repeated here.
- **No `logging:` block, deliberately.** The container takes the host-wide default from `/etc/docker/daemon.json`, which ships its stdout to the log store. A block here would override that default and quietly keep this source out of the store. The log driver is fixed when a container is created, so a change to the daemon default reaches this stack only after the `--force-recreate` carry-over in the stack-recovery runbook.
- **The Compose Manager writes its own override.** `/boot/config/plugins/compose.manager/projects/stack-health/docker-compose.override.yml` carries the Unraid icon and WebUI labels, fed by that plugin's UI, and it wins over anything set here. The `docker-compose.override.yaml` tracked in this directory is an intentional no-op placeholder and is not that file.
