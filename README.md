# homelab

[![README Style](https://img.shields.io/badge/README%20style-standard-2ea44f)](https://github.com/RichardLitt/standard-readme)

[![Buy me uptime](https://img.shields.io/badge/Buy%20me%20uptime%20%F0%9F%96%A5%EF%B8%8F-smoochy84-E9C46A?logo=buymeacoffee&logoColor=000000)](https://www.buymeacoffee.com/smoochy84)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-smoochy-7CC6FE?logo=ko-fi&logoColor=000000)](https://ko-fi.com/smoochy)

> Composable self-hosted stack definitions, environment templates, and
> deployment guidance for a Docker-based homelab built around Komodo,
> SOPS/age, reverse proxying, and service-specific app stacks.

This repository documents a Docker-based homelab layout built around
stack-level `compose.yaml` files, tracked `.env.example` templates, and
deployment documentation. The structure is intended to stay reusable at the
stack level while keeping the operational workflow consistent across the repo.

If this project saves you time or helps your setup, you can support ongoing
maintenance via Ko-fi or Buy Me a Coffee.

This repository is kept in sync automatically. When I update my homelab
configuration, the published repository is refreshed through the synchronization
workflow too.

## Table of Contents

- [Background](#background)
- [What This Repository Contains](#what-this-repository-contains)
- [Stack Coverage](#stack-coverage)
- [Repository Layout](#repository-layout)
- [Using This Repository as a Base](#using-this-repository-as-a-base)
- [Companion Repositories](#companion-repositories)

## Background

Many homelab repositories either reflect a single environment too closely or
stop at isolated examples. This repository keeps the deployment model, config
templates, and surrounding documentation in one place so the stack layout and
operations workflow remain visible together.

The focus is on:

- stack-oriented Docker Compose deployments
- reproducible environment templates
- Komodo-based deployment workflows
- encrypted environment handling with SOPS and age
- documentation that explains how the surrounding deployment model works

## What This Repository Contains

At the root level, this repository gives you:

- one directory per stack or app
- a `compose.yaml` per stack
- a tracked `.env.example` per stack as the configuration starting point
- stack-specific `README.md` files with upstream links and context
- deployment guides under [`docs`](./docs/README.md)

The goal is not to be a generic Docker examples collection. The repository is
designed as a coherent homelab layout where networking, access management,
deployment, monitoring, and media-adjacent services can live in one structure.

## Stack Coverage

The repository currently spans several homelab areas:

- Edge and networking:
  `traefik`, `cloudflared`, `adguard-home-unbound`, `crowdsec`
- Access, control, and dashboards:
  `komodo`, `authentik`, `homepage`, `dozzle`
- Media, requests, indexing, and adjacent tooling:
  `radarr`, `sonarr`, `sabnzbd`, `prowlarr`, `seerr`, `episeerr`, `plex`,
  `tautulli`, `tracearr`, `umlautadaptarr`, `notifiarr`, `yamtrack`
- Utility and infrastructure services:
  `mosquitto`, `registry`, `speedtest-tracker`, `homebridge`,
  `changedetection-io`, `filebrowser-pnp`, `cloudberry-backup`, `uptime-kuma`,
  `apprise`

Not every stack is required. The repository is modular, so individual stacks
can be used independently or as part of a narrower deployment scope.

## Repository Layout

The layout is built to be easy to navigate:

- stack directories contain the deployment files and local stack README
- [`docs`](./docs/README.md) contains cross-stack deployment guidance
- stack READMEs explain what each service is for, what images are used, and
  where the upstream project lives

For the deployment workflow itself, the most important docs are:

- [SOPS, age, File Watcher, Komodo, and Unraid](./docs/sops-age-komodo.md)
- [GitHub workflow docs](./docs/github-workflows/README.md)

## Using This Repository as a Base

One way to work from this repository is:

1. Pick the stack directories that match the target environment.
2. Start from each stack's `.env.example` and fill in the local values.
3. Adjust host paths, domains, and networking for the deployment environment.
4. Follow the documentation in [`docs`](./docs/README.md) for encrypted env
   handling and deployment behavior.
5. Deploy the selected stacks with Komodo or plain Docker Compose, depending on
   the operating model.

This structure is useful when the deployment needs:

- a repo-backed homelab layout rather than isolated Compose snippets
- consistent environment file handling across stacks
- a documented path toward encrypted secrets in stack deployments
- room for environment-specific paths, domains, and operational preferences

## Companion Repositories

- [homelab-automation-scripts](https://github.com/smoochy/homelab-automation-scripts):
  task-focused helper scripts for media and host operations
- [komodo-periphery-sops-age](https://github.com/smoochy/komodo-periphery-sops-age):
  Komodo Periphery image with `sops` and `age` preinstalled
- [caddy-modules](https://github.com/smoochy/caddy-modules):
  custom Caddy image builds used by the `caddy` stack
