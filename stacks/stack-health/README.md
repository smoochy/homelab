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
