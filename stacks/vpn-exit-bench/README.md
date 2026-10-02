# VPN Exit Bench

> Benchmark stack that measures the WireGuard exits the download client already carries, so their ranking rests on measurements

## Stack role

This directory holds `compose.yaml`, `docker-compose.override.yaml`, `README.md` and the tracked `.env.example`. The real `.env` stays local and reaches the host as the encrypted `.env.enc` beside it; see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md) for that workflow.

## Services

- `vpn-exit-bench-config-sync` - one-shot init container that renders one WireGuard config per exit into the appdata the app serves
- `vpn-exit-bench-socket-proxy` - restricted Docker API on a stack-private network, so the container-create grant the app needs stays inside this stack
- `vpn-exit-bench`

## Upstream

### `vpn-exit-bench-config-sync`

- Website: [https://github.com/mlo-Tek/VPN-Exit-Bench](https://github.com/mlo-Tek/VPN-Exit-Bench)
- GitHub: [https://github.com/mlo-Tek/VPN-Exit-Bench](https://github.com/mlo-Tek/VPN-Exit-Bench)

### `vpn-exit-bench-socket-proxy`

- Website: [https://hub.docker.com/r/tecnativa/docker-socket-proxy](https://hub.docker.com/r/tecnativa/docker-socket-proxy)
- GitHub: [https://github.com/Tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy)

### `vpn-exit-bench`

- Website: [https://github.com/mlo-Tek/VPN-Exit-Bench](https://github.com/mlo-Tek/VPN-Exit-Bench)
- GitHub: [https://github.com/mlo-Tek/VPN-Exit-Bench](https://github.com/mlo-Tek/VPN-Exit-Bench)

## Where the configs come from

There is exactly one copy of the WireGuard key material in this repository, and it is the qbittorrent stack's `.env`. This stack holds none of it. The qbittorrent compose file renders those ten ranked exits into `/mnt/user/appdata/qbittorrent/wireguard/exits.json`, and the init container above turns that file into `/mnt/user/appdata/vpn-exit-bench/config/vpns/Proton/<rank>-<label>.conf`, mode 0400.

The first directory level under `/config/vpns` is what the app shows as the provider name, hence `Proton`. The files have to be real files on the host rather than a compose `configs:` overlay: for every benchmark the app creates a worker container and bind-mounts the selected config from the host path backing its own `/config`, and a container-local overlay would leave the worker mounting an empty directory.

The init container also deletes a `.conf` it did not write in this run, so a renamed or re-ranked exit does not stay on offer as a stale entry.

## Before a benchmark run

Stop the `qbittorrent` container first, and start it again when the run is done.

A WireGuard key pair may only be live in one tunnel at a time. The server moves the peer to whichever endpoint registered last, so a benchmark on any of these exits takes the client's tunnel and with it the forwarded port. Every config this stack serves is one of qbittorrent's own exits, so this is not a risk to avoid but a precondition to meet.

The thelounge stack is unaffected either way: its pinned exit is deliberately not part of qbittorrent's rendered exit list and therefore not part of this stack's configs.

## Exposure

Internal router only. The WebUI can create containers through the socket proxy, so it gets no `-external` and no `-bypass` router, and HTTP basic auth is on. Port 8787 is published on the Unraid host for LAN access and stays off the internet.

## Reference line speed

`REFERENCE_DOWN_MBPS` and `REFERENCE_UP_MBPS` are the connection's own rated throughput, 600 and 300, so a result reads as a share of what the line can actually deliver. Upstream defaults to 500/200.

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `vpn-exit-bench`.
