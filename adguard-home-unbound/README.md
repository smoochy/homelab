# AdGuard Home + Unbound

> DNS filtering and recursive DNS resolution for the homelab edge

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `adguard-home-unbound`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../docs/sops-age-komodo.md).

In this setup, `adguard-home-sync` is used because a second redundant AdGuard instance runs on another device, such as a Raspberry Pi, so the local network can use two DNS servers for failover.

If you only run a single DNS server, you do not need `adguard-home-sync` and can simplify the stack accordingly.

## Services

- `adguard-home-sync`
- `adguard-home-unbound`

## Upstream

### `adguard-home-sync`

- Website: [https://github.com/bakito/adguardhome-sync](https://github.com/bakito/adguardhome-sync)
- GitHub: [https://github.com/bakito/adguardhome-sync](https://github.com/bakito/adguardhome-sync)

### `adguard-home-unbound`

- Website: [https://adguard.com/en/adguard-home/overview.html](https://adguard.com/en/adguard-home/overview.html)
- GitHub: [https://github.com/AdguardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
