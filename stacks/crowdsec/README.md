# CrowdSec

> Security telemetry, bouncers, and dashboard components for perimeter defense

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `crowdsec`.

## Services

- `crowdsec`
- `crowdsec-dashboard`
- `crowdsec-bouncer-prune`
- `crowdsec-blocklist-import`
- `crowdsec-manager`
- `crowdsec-firewall-bouncer`

## Upstream

### `crowdsec`

- Website: [https://www.crowdsec.net/](https://www.crowdsec.net/)
- GitHub: [https://github.com/crowdsecurity/crowdsec](https://github.com/crowdsecurity/crowdsec)

### `crowdsec-dashboard`

- Website: [https://www.metabase.com/](https://www.metabase.com/)
- GitHub: [https://github.com/metabase/metabase](https://github.com/metabase/metabase)

### `crowdsec-bouncer-prune`

- Website: [https://www.crowdsec.net/](https://www.crowdsec.net/)
- GitHub: [https://github.com/crowdsecurity/crowdsec](https://github.com/crowdsecurity/crowdsec)

### `crowdsec-blocklist-import`

- Website: [https://github.com/wolffcatskyy/crowdsec-blocklist-import](https://github.com/wolffcatskyy/crowdsec-blocklist-import)
- GitHub: [https://github.com/wolffcatskyy/crowdsec-blocklist-import](https://github.com/wolffcatskyy/crowdsec-blocklist-import)

### `crowdsec-manager`

- Website: [https://crowdsec-manager.hhf.technology/](https://crowdsec-manager.hhf.technology/)
- GitHub: [https://github.com/hhftechnology/crowdsec_manager](https://github.com/hhftechnology/crowdsec_manager)

### `crowdsec-firewall-bouncer`

- Website: [https://github.com/shgew/cs-firewall-bouncer-docker](https://github.com/shgew/cs-firewall-bouncer-docker)
- GitHub: [https://github.com/shgew/cs-firewall-bouncer-docker](https://github.com/shgew/cs-firewall-bouncer-docker)

## State Database

CrowdSec keeps its machines, alerts and decisions in a SQLite database under `appdata/crowdsec/data/crowdsec.db`, which the `crowdsec-dashboard` service mounts as well - the Metabase container reads that same file as its data source, a leftover of the removed `cscli dashboard` setup.

- `USE_WAL=true` puts the database into write-ahead logging mode, so readers no longer block the writer.
- Without it, concurrent access degrades into permanent `database is locked` errors: LAPI requests run until their retry deadline, the local machine login fails with 401, and both bouncers keep re-pulling their decision streams.
- The setting is applied by the image entrypoint, which writes `db_config.use_wal` into the mounted `config.yaml` on start.

## Blocklist Import

`crowdsec-blocklist-import` pulls roughly 28 public threat feeds and writes them into the local API as decisions, which the firewall bouncer then mirrors into its ipset on the host.

- It authenticates twice: with the machine `blocklist-import` to write decisions, and with the bouncer key `blocklist-import` to read the existing ones for deduplication. Both were registered through `cscli machines add` and `cscli bouncers add` and live in the stack `.env` as `CROWDSEC_BLOCKLIST_IMPORT_MACHINE_PASSWORD` and `CROWDSEC_BLOCKLIST_IMPORT_LAPI_KEY`.
- `INTERVAL=86400` keeps the container alive as its own scheduler, so no cron job or timer owns the cadence. `DECISION_DURATION=26h` outlasts that cycle, so a late round leaves no gap.
- `MAX_DECISIONS=120000` caps existing plus new decisions. The hard ceiling is the bouncer's own ipset: it creates `crowdsec-blacklists-<n>` with `maxelem 131072`, measured on the first run, and an overflowing set silently stops taking elements while the decisions keep piling up in the SQLite file the dashboard queries live. The cap leaves room for the other origins in the same set. The feeds total well past half a million entries, so this number is what is enforced, not the feeds.
- `ALLOWLIST` carries the RFC1918 ranges. The bouncer enforces on the host with `NET_ADMIN`, so a false positive on a LAN range would cut off access to the machine that has to fix it.

## Traefik Integration

The Traefik remediation path is handled by the official `crowdsec-bouncer-traefik-plugin` inside the [`traefik`](../traefik/README.md) stack.

- `CROWDSEC_TRAEFIK_BOUNCER_API_KEY` is shared with the Traefik stack.
- The `crowdsec` service registers that key through `BOUNCER_KEY_TRAEFIK`.
- `crowdsec-manager` targets the shared `/etc/traefik/dynamic.yml` file.
- No standalone Traefik bouncer container is used in this stack anymore.
