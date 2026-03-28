# CrowdSec

> Security telemetry, bouncers, and dashboard components for perimeter defense

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `crowdsec`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `crowdsec`
- `crowdsec-dashboard`
- `crowdsec-manager`
- `crowdsec-firewall-bouncer`

## Upstream

### `crowdsec`

- Website: [https://www.crowdsec.net/](https://www.crowdsec.net/)
- GitHub: [https://github.com/crowdsecurity/crowdsec](https://github.com/crowdsecurity/crowdsec)

### `crowdsec-dashboard`

- Website: [https://www.metabase.com/](https://www.metabase.com/)
- GitHub: [https://github.com/metabase/metabase](https://github.com/metabase/metabase)

### `crowdsec-manager`

- Website: [https://crowdsec-manager.hhf.technology/](https://crowdsec-manager.hhf.technology/)
- GitHub: [https://github.com/hhftechnology/crowdsec_manager](https://github.com/hhftechnology/crowdsec_manager)

### `crowdsec-firewall-bouncer`

- Website: [https://github.com/shgew/cs-firewall-bouncer-docker](https://github.com/shgew/cs-firewall-bouncer-docker)
- GitHub: [https://github.com/shgew/cs-firewall-bouncer-docker](https://github.com/shgew/cs-firewall-bouncer-docker)

## Traefik Integration

The Traefik remediation path is handled by the official `crowdsec-bouncer-traefik-plugin` inside the [`traefik`](../traefik/README.md) stack.

- `CROWDSEC_TRAEFIK_BOUNCER_API_KEY` is shared with the Traefik stack.
- The `crowdsec` service registers that key through `BOUNCER_KEY_TRAEFIK`.
- No standalone Traefik bouncer container is used in this stack anymore.
