# AutoKuma

> Label-driven automation that creates and maintains Uptime Kuma monitors from container labels

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `autokuma`.

## Services

- `autokuma`

## Upstream

- Website: [https://github.com/BigBoot/AutoKuma](https://github.com/BigBoot/AutoKuma)
- GitHub: [https://github.com/BigBoot/AutoKuma](https://github.com/BigBoot/AutoKuma)

## Operating Notes

- **Ownership split.** 30 monitors are label-managed by this stack. 16 monitors (11 push, 4 dns, 1 http) stay hand-managed permanently, because nothing container-shaped exists behind them. 13 of the 30 are migrated: `registry` in wave one (#1776), the ten `docker` monitors in wave two (#1798), and `traefik - traefik` plus `adguard-home-unbound - adguard-home-sync` in wave 3a (#1858). The remaining 17 are `http` monitors and go in one pass as wave 3b.
- **The Raspberry Pi AdGuard http monitor stays hand-managed.** `Adguard Home Raspberry` (`https://adguard.example.com`) points at an AdGuard instance on a Raspberry Pi outside this Docker host, and its Traefik router lives in the file provider rather than on a container. Hanging its label on `adguard-home-sync` or `adguard-home-unbound` would tie the monitor to the lifecycle of a container it has nothing to do with, and give it a name pointing at a stack it does not belong to - the exact failure `<stack> - <dienst>` exists to prevent. It keeps the `adguard-pi` prefix the dns monitors already use. This is why the label-bound count reads 30 and not 31.
- **`authentik-worker` has a label and no monitor.** The `authentik` stack is not deployed on this host, so AutoKuma never sees the label and cannot create the monitor. Its hand-built monitor was deleted with the rest of wave two, which is why the monitor count reads 45 rather than 46; deploying the stack creates the monitor, paused, from the `active=false` label the compose file already carries.
- **`<stack>` is the compose project, not `restore_stack`.** `com.smoochy.komodo.restore_stack` names `gluetun` and `browserless-v2` after themselves, because it is a restore target rather than a statement of stack identity. Their monitors are `sabnzbd - gluetun` and `changedetection-io - browserless-v2`, so the name always says which stack to open. The push monitors are pushed to by host-side scripts, not by a container AutoKuma can see, and their `pushToken` is the identity a rebuild would destroy; the dns monitors probe two resolvers, one of which runs on a Raspberry Pi outside this Docker host entirely. Neither has a container to hang a label on, so the split is a decision, not a migration backlog. They still carry the binding naming scheme, and they are edited in the Kuma UI or through a Socket.IO action, never by writing `kuma.db`.
- **Naming is binding.** Every monitor name follows `<stack> - <dienst>`. The Uptime Kuma Discord embed carries no tags, so the name is the only carrier of stack identity. For the hand-managed monitors the prefix is the thing to touch when it breaks: `qBit` for the qBittorrent host jobs, `stack-health` for the poller, `adguard-home-unbound` and `adguard-pi` for the two resolvers.
- **No default settings.** `AUTOKUMA__DEFAULT_SETTINGS` is deliberately unset. Every monitor carries its full configuration at its own label, and a migrated monitor keeps the values it had before the migration rather than inheriting a house default.
- **`on_delete=keep`.** A removed container leaves its monitor behind, to be deleted by hand. This is the price of the 2.0.0 pin: the "entity reappeared" guard that makes a redeploy inside the delete grace period safe is fixed in 2.1.0-rc.1 only, and a Kuma-side delete takes the heartbeat history with it via CASCADE.
- **`/data` is not a cache.** It holds the label-id to monitor-id mapping AutoKuma needs to recognise its own monitors after a container recreate.
- **`TZ` matters on both sides.** Removing `TZ` from the `uptime-kuma` container shifts every maintenance window by the offset.
- **Authentication.** Uptime Kuma API keys cannot authenticate a Socket.IO client, and Kuma 2.x is single-user, so AutoKuma logs in as the Kuma admin. The password lives only in the SOPS-encrypted `.env.enc`.

## Migration Wave Procedure

One stack per wave. Proven on `registry` (issue #1776), including a real rollback and a redo.

**Label reference.** Names do not work for entities AutoKuma did not create: `docker_host_name`, `notification_name_list`, `parent_name` and `tag_names` are resolved only against AutoKuma's own store in `/data`, and a name it does not know aborts the create with `NameNotFound`. The hand-built `DockerProxy` docker host and the hand-built `smooBot` notification are therefore referenced by Uptime Kuma's numeric id instead, through `docker_host` and `notification_id_list`:

```yaml
      - kuma.<id>.docker.name=<stack> - <dienst>
      - kuma.<id>.docker.docker_container=<container>
      - kuma.<id>.docker.docker_host=1
      - kuma.<id>.docker.interval=300
      - kuma.<id>.docker.max_retries=1
      - kuma.<id>.docker.retry_interval=300
      - kuma.<id>.docker.resend_interval=0
      - 'kuma.<id>.docker.notification_id_list={"1": true}'
```

The `notification_id_list` value is a JSON object and has to be quoted, or the `": "` inside it turns the list entry into a YAML mapping. `timeout` has no label on this monitor type and is dropped silently.

The `http` block carries more, because the check itself is configured rather than derived from a container:

```yaml
      - kuma.<id>.http.name=<stack> - <dienst>
      - kuma.<id>.http.url=https://<host>
      - kuma.<id>.http.method=GET
      - 'kuma.<id>.http.accepted_statuscodes=["200-299"]'
      - kuma.<id>.http.max_redirects=10
      - kuma.<id>.http.http_body_encoding=json
      - kuma.<id>.http.timeout=4
      - kuma.<id>.http.interval=300
      - kuma.<id>.http.max_retries=1
      - kuma.<id>.http.retry_interval=300
      - kuma.<id>.http.resend_interval=0
      - kuma.<id>.http.ignore_tls=false
      - kuma.<id>.http.expiry_notification=true
      - kuma.<id>.http.upside_down=false
      - 'kuma.<id>.http.notification_id_list={"1": true}'
```

`timeout` does exist on this type, unlike on `docker`. `http_body_encoding` is set on every hand-built monitor and has to be repeated, or the rebuild differs in a field nobody looks at.

`accepted_statuscodes` takes a quoted JSON array, not the bare `200-299` that both the upstream documentation and the field-to-label table in #1784 show. The bare form is a parse error: a throwaway probe container in #1858 produced `Error while trying to parse labels: invalid type: integer 200, expected a sequence at line 1 column 3` every five seconds and created nothing at all. That is the second thing the probe proved: **a single malformed label aborts the whole sync**, not just the monitor carrying it, so a wave with one bad label leaves every monitor in it uncreated. Probe the labels on a throwaway container before merging them onto a real stack.

**No credentials and no headers on the http monitors, with one exception.** #1809 probed all twenty URLs from inside the `uptime-kuma` container in four credential variants: nineteen answer 200 with no credentials at all, and no monitor carries a header today. The `basic_auth_user` and `basic_auth_pass` columns on those nineteen are leftovers of a Traefik middleware that no longer exists - they are dropped in the rebuild deliberately, which is the one place a migrated monitor is not field-identical to the one it replaces. The exception is `adguard-home-unbound - adguard-home-sync`, which returns 401 without auth and needs a password of its own rather than the one the others carried. It is the only monitor secret in the fleet, a `KUMA_BASIC_AUTH_PASS` key in that stack's SOPS `.env` interpolated into the label per #1794, and it needs `authMethod=basic` alongside the user and password.

**The wave itself.** Wave two ran all ten monitors across eight stacks in one pass, and the deploys reach the host through the GitHub webhook, so step 1 has to happen **before** the merge: merging to `main` recreates the containers on its own, and a backup taken afterwards already contains the new labels.

1. Take the backup: `docker stop autokuma`, `docker stop uptime-kuma`, copy `kuma.db` plus `kuma.db-wal` and `kuma.db-shm` if they exist out of `/mnt/user/appdata/uptimekuma`, `tar` up `/mnt/user/appdata/autokuma`, `docker start uptime-kuma`. AutoKuma stays down for the whole wave. Never restore into a live Kuma: it holds monitor state in memory and pushes it over the socket.
2. Merge the labels and deploy the stack through Komodo, so the container is recreated carrying them.
3. `docker start autokuma`. It creates a **second** monitor next to the hand-built one - it never adopts (#1775) - so the old monitor is still there as the fallback while the new one is checked.
4. Compare the new monitor field by field against the old one, and confirm the row in `monitor_notification`.
5. Delete the old monitor: `docker stop autokuma`, `docker stop uptime-kuma`, `sqlite3 kuma.db 'PRAGMA foreign_keys=ON; delete from monitor where id=<old>;'`, `docker start uptime-kuma`, wait for Kuma to answer, then `docker start autokuma`. The delete takes the heartbeat history with it - that is the accepted price of the rebuild model.

Starting both containers back to back costs one failed sync: AutoKuma gives Kuma about nine seconds and then logs `Timeout while trying to connect to Uptime Kuma server`. It recovers on its own within the next cycle and creates nothing twice, so the warning is cosmetic - but the two starts are worth separating, because a warning that always appears is a warning nobody reads.

**Rollback.** Same path backwards, and the order is what makes it work: stop `autokuma` **first**, then stop Kuma, restore the copied files, start Kuma. AutoKuma must not be running while the restore happens, because its `/data` still maps its label id to a monitor id the restored database no longer contains, and on the next tick it would simply create a third monitor. Restoring the `/data` tar together with `kuma.db` puts both sides back on the same state.

**Reading `kuma.db` while Kuma runs.** Copy `kuma.db-wal` and `kuma.db-shm` along with `kuma.db`, or the copy is silently stale by exactly the change being checked.

## Upgrade to 2.1.0

When Renovate proposes `2.1.0` stable, that pull request carries three changes together, not just the digest:

1. `AUTOKUMA__ON_DELETE=delete` with `AUTOKUMA__DELETE_GRACE_PERIOD=1800`.
2. The standard healthcheck against `http://127.0.0.1:8090/health`, replacing the marker comment in `compose.yaml`.
3. A `kuma.*` label on AutoKuma itself, so the thing that watches everything is watched too.

Do not merge that Renovate pull request as a bare digest bump.
