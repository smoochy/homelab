# Sonarr Queue Tools

> One custom script Sonarr runs itself, `queue_housekeeping.sh`: on a grab it cancels a superseded download, on an import event it imports what Sonarr left stuck in the queue. Only Sonarr's own events trigger it, so no host cron is needed.

These are the Sonarr twins of [the Radarr tools](../../../radarr/scripts/tools/README.md), adapted for series and episodes. They are a copy rather than a shared bundle on purpose: each container mounts only its own `/config`, so neither can read a file living in the other's appdata.

Both are delivered to `/mnt/user/appdata/sonarr/scripts/tools` by [`scripts/deliver.sh`](../../../../scripts/deliver.sh), which the Sonarr container sees as `/config/scripts/tools`.

## Credentials

The script carries no API key. `sonarr_api.sh` reads `ApiKey`, `Port` and `UrlBase` out of `/config/config.xml` at runtime and talks to `http://127.0.0.1:<port><urlbase>`. Nothing is committed, nothing is templated into `compose.yaml`, and a key rotated in the UI is picked up on the next run.

## On Grab: supersede

Sonarr grabs a higher-scoring release while a lower-scoring one is still downloading and then leaves both jobs running: the queue is consulted when a release is evaluated, but no path removes an item that is already in flight. Both complete, both import in turn, and the second import wins. The upstream answer is a Delay Profile, which buys the deduplication with latency on every grab; this cancels the loser after the fact instead, so grabs stay immediate.

On an `On Grab` event it reads `/api/v3/queue/details` for that series and removes every entry that scores strictly below the release just grabbed **and** whose episodes are entirely covered by it, with `removeFromClient=true`, `blocklist=false` and `skipRedownload=true`. `skipRedownload` matters: without it Sonarr searches a replacement for the release it just superseded and the pair comes straight back.

The episode subset check is the difference from the Radarr version. A season pack that contains the grabbed episode also contains episodes this grab does not replace, so it survives; a pack is only cancelled when the new grab covers all of it.

## On Import, On Manual Interaction Required: import sweep

An item that finished downloading can sit in the queue as `completed` / `importPending` for two reasons: Sonarr refuses the import as `Not a Custom Format upgrade` against a file a sibling release just delivered, or it cannot match the release name to a series at all - which is what a German release of an English show looks like until the indexer proxy learns its title.

The script sweeps those items, asks `/api/v3/manualimport` for their candidates with `filterExistingFiles=false`, and imports through the real `ManualImport` command. The series and episode come from the **queue entry**, not from the candidate's own title match, so an unmatched release still imports. `Not a Custom Format upgrade` is the only rejection it clears; anything else - a sample, an unparseable name - stays refused. Before it replaces existing files it compares scores per episode and acts only on a strict upgrade for every episode the file covers, so a worse candidate never downgrades the library.

`--dry-run` reports what it would do and calls nothing.

## Watcher and log file

Sonarr sends no event when an item turns `importBlocked` after the last event already ran, so a sweep that finds nothing at grab time is never repeated. Every Grab, Import and Manual Interaction event therefore also starts a detached `--watch` run inside the container (one at a time, guarded by the lock directory `/tmp/queue_housekeeping.watch`). It sweeps every 30 seconds while the queue has items, acts on an item only once it was stuck for two consecutive ticks so it never races Sonarr's own import, tries each stuck item once, and exits after three empty ticks or six hours. `HOUSEKEEPING_WATCH=0` disables the spawn.

Every run appends to `/config/logs/queue_housekeeping.log` (override with `HOUSEKEEPING_LOG`, one rotated generation at 1 MB): timestamp, pid, event, the names of the `sonarr_*` variables received and the queue overview with status and tracked download state.

## Install

Settings > Connect > Add > Custom Script, once:

| Script | Path | Triggers |
| --- | --- | --- |
| `queue_housekeeping.sh` | `/config/scripts/tools/queue_housekeeping.sh` | On Grab, On Import, On Manual Interaction Required |

The script dispatches on `sonarr_eventtype`: `Grab` runs the supersede, `Download` and `ManualInteractionRequired` run the import sweep, and any other event does nothing. When replacing the two old Connect entries (`supersede_queue.sh`, `import_stuck_items.sh`), delete both and add this one.

`On Manual Interaction Required` is not optional cover: a title-match failure raises no import event at all, so without it the stuck item that most needs the sweep never triggers one.

It exits clean on Sonarr's `Test` event, so the connection test passes without touching anything. Output goes to Sonarr's own log.

With no event in the environment it runs the import sweep, so it also works by hand:

```sh
docker exec sonarr /config/scripts/tools/queue_housekeeping.sh --dry-run
```

## Tests

No Sonarr required - a fake `curl` serves fixture responses and records every request:

```sh
bash stacks/sonarr/scripts/tools/tests/test_supersede_queue.sh
bash stacks/sonarr/scripts/tools/tests/test_import_stuck_items.sh
```
