# AdGuard Home + Unbound

> DNS filtering and recursive DNS resolution for the homelab edge

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `adguard-home-unbound`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

In this setup, `adguard-home-sync` is used because a second redundant AdGuard instance runs on another device, such as a Raspberry Pi, so the local network can use two DNS servers for failover.

If you only run a single DNS server, you do not need `adguard-home-sync` and can simplify the stack accordingly.

A sanitized `adguard-home-sync.yaml.example` in this directory documents the expected sync layout and the internal `http://adguard-home-unbound` replica target without storing live credentials.

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

## Configuration Notes

Use [`adguard-home-sync.yaml.example`](./adguard-home-sync.yaml.example) as the tracked baseline for `adguard-home-sync`. It documents the expected sync structure without storing live usernames or passwords.

For this stack, keep the local replica URL on `http://adguard-home-unbound` rather than `http://192.0.2.3`. The container reaches the AdGuard API through `smoonet`, while `192.0.2.3` remains the LAN-facing DNS address on `br0`.
