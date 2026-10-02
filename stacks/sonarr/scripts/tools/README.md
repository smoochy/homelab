# Sonarr Queue Tools

> Two custom scripts Sonarr runs itself: one cancels a superseded download, the other imports what Sonarr left stuck in the queue.

These are the Sonarr twins of [the Radarr tools](../../../radarr/scripts/tools/README.md), adapted for series and episodes. They are a copy rather than a shared bundle on purpose: each container mounts only its own `/config`, so neither can read a file living in the other's appdata.

Both are delivered to `/mnt/user/appdata/sonarr/scripts/tools` by [`scripts/deliver.sh`](../../../../scripts/deliver.sh), which the Sonarr container sees as `/config/scripts/tools`.

## Credentials

Neither script carries an API key. `sonarr_api.sh` reads `ApiKey`, `Port` and `UrlBase` out of `/config/config.xml` at runtime and talks to `http://127.0.0.1:<port><urlbase>`. Nothing is committed, nothing is templated into `compose.yaml`, and a key rotated in the UI is picked up on the next run.

## `supersede_queue.sh` - On Grab

Sonarr grabs a higher-scoring release while a lower-scoring one is still downloading and then leaves both jobs running: the queue is consulted when a release is evaluated, but no path removes an item that is already in flight. Both complete, both import in turn, and the second import wins. The upstream answer is a Delay Profile, which buys the deduplication with latency on every grab; this cancels the loser after the fact instead, so grabs stay immediate.

On an `On Grab` event it reads `/api/v3/queue/details` for that series and removes every entry that scores strictly below the release just grabbed **and** whose episodes are entirely covered by it, with `removeFromClient=true`, `blocklist=false` and `skipRedownload=true`. `skipRedownload` matters: without it Sonarr searches a replacement for the release it just superseded and the pair comes straight back.

The episode subset check is the difference from the Radarr version. A season pack that contains the grabbed episode also contains episodes this grab does not replace, so it survives; a pack is only cancelled when the new grab covers all of it.

## `import_stuck_items.sh` - On Import, On Manual Interaction Required

An item that finished downloading can sit in the queue as `completed` / `importPending` for two reasons: Sonarr refuses the import as `Not a Custom Format upgrade` against a file a sibling release just delivered, or it cannot match the release name to a series at all - which is what a German release of an English show looks like until the indexer proxy learns its title.

The script sweeps those items, asks `/api/v3/manualimport` for their candidates with `filterExistingFiles=false`, and imports through the real `ManualImport` command. The series and episode come from the **queue entry**, not from the candidate's own title match, so an unmatched release still imports. `Not a Custom Format upgrade` is the only rejection it clears; anything else - a sample, an unparseable name - stays refused. Before it replaces existing files it compares scores per episode and acts only on a strict upgrade for every episode the file covers, so a worse candidate never downgrades the library.

`--dry-run` reports what it would do and calls nothing.

## Install

Settings > Connect > Add > Custom Script, once per script:

| Script | Path | Triggers |
| --- | --- | --- |
| `supersede_queue.sh` | `/config/scripts/tools/supersede_queue.sh` | On Grab |
| `import_stuck_items.sh` | `/config/scripts/tools/import_stuck_items.sh` | On Import, On Manual Interaction Required |

`On Manual Interaction Required` is not optional cover: a title-match failure raises no import event at all, so without it the stuck item that most needs the sweep never triggers one.

Both exit clean on Sonarr's `Test` event, so the connection test passes without touching anything. Output goes to Sonarr's own log.

`import_stuck_items.sh` also runs standalone:

```sh
docker exec sonarr /config/scripts/tools/import_stuck_items.sh --dry-run
```

## Tests

No Sonarr required - a fake `curl` serves fixture responses and records every request:

```sh
bash stacks/sonarr/scripts/tools/tests/test_supersede_queue.sh
bash stacks/sonarr/scripts/tools/tests/test_import_stuck_items.sh
```
