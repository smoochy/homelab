# Homebridge

> Bridge service for exposing non-HomeKit devices into Apple Home

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `homebridge`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

`homebridge` uses both `br0` and `smoonet`: HomeKit discovery stays on the LAN-facing `br0` address, while Docker-internal services such as `mosquitto` should be reached by hostname on `smoonet`.

## Services

- `homebridge`

## Upstream

- Website: [https://homebridge.io/](https://homebridge.io/)
- GitHub: [https://github.com/homebridge/homebridge](https://github.com/homebridge/homebridge)

## Configuration Notes

If `homebridge-mqttthing` or similar plugins need the local broker, use `mqtt://mosquitto:1883`. This avoids the `EHOSTUNREACH` failure that occurs when the container tries to reach the host LAN IP for a broker that already exists on the shared Docker network.
