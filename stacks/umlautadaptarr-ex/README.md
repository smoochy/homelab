# UmlautAdaptarrEX

> Umlaut and foreign-title correction for Sonarr and Radarr searches, proxied through Prowlarr

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `umlautadaptarr-ex`.

## Services

- `umlautadaptarr-ex`

## Ports

| Port | Purpose |
| --- | --- |
| 5005 | Fastify API the *Arrs call directly |
| 5006 | HTTP-CONNECT proxy Prowlarr points its indexers at |
| 5007 | Next.js web UI and setup wizard |

Each port has to be mapped 1:1 between host and container. The app derives the URLs it hands out from these values, so a remapped host port breaks the UI's `/api` proxying and the indexer URLs rather than just moving the endpoint.

## Rollback to the old stack

The cutover was a hard one and the predecessor is gone from this repository. Rolling back means reverting the commit that removed `stacks/umlautadaptarr/`, redeploying that stack in Komodo, and pointing Prowlarr's indexers back at its proxy. Both stacks publish 5005 and 5006, so only one of them can run at a time.

## Configuration lives in the database, not the environment

UmlautAdaptarrEX has no environment variable for any *Arr connection. Host, API key, enabled flag, the admin login, the Prowlarr proxy credentials and the language plugin toggles all live in the SQLite database at `/data/umlautadaptarrex.db`, reachable only through the setup wizard on port 5007.

The environment covers the three ports, `PUID`/`PGID`, `TZ`, `LOG_LEVEL`, headless mode and `UA_ALLOW_PRIVATE_INSTANCE_HOSTS`. Those are re-read from the environment on every boot and never written back to the database, so they cannot drift and a redeploy cannot clobber them.

## Backup and restore

`/data` is bind-mounted to `/mnt/user/appdata/umlautadaptarr-ex/data`, so the database is covered by the Unraid appdata backup from the first deploy. There is no separate dump job; a second backup path for one file the appdata backup already carries would add a schedule without adding a recovery guarantee.

To restore:

1. Stop the stack in Komodo.
2. Restore `/mnt/user/appdata/umlautadaptarr-ex/data/umlautadaptarrex.db` from the appdata backup, preserving ownership matching `PUID`/`PGID` (99:100). A database the container cannot write is worse than no database.
3. `DeployStack`, never `RestartStack` - see the stack recovery runbook.
4. If no backup is usable: deploy with an empty `/data`, re-run the setup wizard, and re-enter both *Arr hosts and their API keys. The keys are readable from the Sonarr and Radarr UIs, so this costs minutes rather than data.

## Open after the first deploy

The web UI on 5007 talks to the API on 5005. Whether it does so over container loopback or by deriving the API origin from the browser's own location is not decidable from the compose file. If the UI is reached through Traefik at `ua.example.com` and the latter is true, client-side requests land on the wrong origin. Check the browser devtools network tab once after the first deploy; nothing in this stack can settle it beforehand.

## Upstream

- Website: [https://github.com/xpsony/UmlautAdaptarrEX](https://github.com/xpsony/UmlautAdaptarrEX)
- GitHub: [https://github.com/xpsony/UmlautAdaptarrEX](https://github.com/xpsony/UmlautAdaptarrEX)

## Notes

- This stack replaces `umlautadaptarr`, the C#/.NET original it was rewritten from; that stack was removed on 2026-08-27.
- Every *Arr connection lives in the SQLite database under `/data`, not in the environment; the setup wizard on port 5007 is the only way in.
