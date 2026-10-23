# nzbfast

> Usenet downloader with a SABnzbd-compatible API, run behind the VPN next to SABnzbd as the preferred client

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `nzbfast`.

## Services

- `nzbfast`

## Failover

nzbfast has priority 1 and sabnzbd priority 10 in Radarr, Sonarr and the sonarr lane, but priority alone does not fail over when nzbfast is down. [`scripts/nzbfast_failover.py`](../../scripts/nzbfast_failover.py) is run on a timer and toggles only the `enable` flag of the download client named `nzbfast` in each app (`--arr`, repeatable), never the sabnzbd entry and never queue items.

- It probes the SAB-style queue API of nzbfast and of sabnzbd each run. `--fail-after N` consecutive failed probes (default 3) disable the client, `--recover-after M` consecutive healthy probes (default 5) enable it again; the counters live in the `--state` file, so a single blip never flaps it.
- If sabnzbd is unhealthy too, nothing changes and the run exits 2 so the caller can alert. Transitions are logged to stderr. Running twice with the same state changes nothing.
- Keys come from the environment: `NZBFAST_APIKEY`, `SAB_APIKEY`, `ARR_APIKEYS` (comma list in `--arr` order).
- Manual override, sticky until released: `nzbfast_failover.py ... --set disabled` (or `enabled`), and `--set auto` hands control back to the probe.

## Image

The service runs `nzbfast:local`, built by Komodo from [`image/Dockerfile`](image/Dockerfile): the digest-pinned `nzbfast/nzbfast:1.1.5` (Debian bookworm) plus `jq`, `python3`, `python3-yaml` and `wget`, which the staging script needs. `7z` (for `extract_iso.sh`), `bash` and `curl` already ship in the base image. After changing the build context, run `scripts/src-rev.sh` so the `SRC_REV` marker moves and Komodo deploys.

## Post-processing scripts

The mirrored script tree `/mnt/user/appdata/qbittorrent/scripts` is mounted read-only at `/scripts`, the same scripts sabnzbd runs. nzbfast has no scripts directory and no per-category assignment; scripts are registered only through the global `script` setting in `/config/settings.json`, a comma or semicolon separated chain of absolute paths, run in order inside the container as PUID:PGID (99:100). Set it once through the dashboard (Settings) or by editing the file with the container stopped:

```json
"script": "/scripts/current/sabnzbd/extract_iso.sh,<staging script from the same directory>"
```

The staging script hard-links the finished files under their final name, so nzbfast's "Rename finished downloads" must stay OFF (#1052).

## Komodo resource

The Komodo stack `nzbfast` mirrors `cryo-dash`: `run_directory` `stacks/nzbfast`, `file_paths` `compose.yaml` and `docker-compose.override.yaml` (kept as `services: {}`), `config_files` `.env.enc` with `requires: Redeploy`, `env_file_path` `.env` and the SOPS `pre_deploy` from [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md). It was created and first deployed after gluetun on 2026-10-23.

## Gluetun dependency

nzbfast joins the network namespace of the `gluetun` container, which belongs to the sabnzbd compose project. When gluetun is restarted or recreated, nzbfast keeps running in the old, now stale namespace: it stays `healthy` and keeps its own `StartedAt`, but no longer shares gluetun's interface. Neither the `com.smoochy.komodo.restore_stack=gluetun` label nor a plain `DeployStack` repairs this. The label is read only by the boot-time scripts in `host/smooRaid/user-scripts/`, and a `DeployStack` without a config change does not recreate the container. A Docker restart of the container does re-join the current namespace, so after any gluetun restart or sabnzbd stack redeploy run the Komodo procedure `nzbfast-rejoin-gluetun` (a single `RestartStack nzbfast`) and compare `docker exec nzbfast readlink /proc/self/ns/net` with the same command in `gluetun`.

## Upstream

- Website: [https://github.com/nzbfast/nzbfast](https://github.com/nzbfast/nzbfast)
- GitHub: [https://github.com/nzbfast/nzbfast](https://github.com/nzbfast/nzbfast)
