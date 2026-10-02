# Radarr Queue Tools

> Two custom scripts Radarr runs itself: one cancels a superseded download, the other imports what Radarr left stuck in the queue.

Both are delivered to `/mnt/user/appdata/radarr/scripts/tools` by [`scripts/deliver.sh`](../../../../scripts/deliver.sh), which the Radarr container sees as `/config/scripts/tools`. Radarr mounts `/config` and `/data` and nothing else, so that is the only path it can execute from.

## Credentials

Neither script carries an API key. `radarr_api.sh` reads `ApiKey`, `Port` and `UrlBase` out of `/config/config.xml` at runtime and talks to `http://127.0.0.1:<port><urlbase>`. Nothing is committed, nothing is templated into `compose.yaml`, and a key rotated in the UI is picked up on the next run.

## `supersede_queue.sh` - On Grab

Radarr grabs a higher-scoring release while a lower-scoring one for the same movie is still downloading, and then leaves both jobs running. `QueueSpecification.cs` is the only place a candidate is compared against what is already queued, and every branch in it ends in `Reject` or `Accept`; no path removes the existing item. Both complete, both import in turn, and the second import wins.

The upstream answer is a Delay Profile, which waits out a window before grabbing anything. That buys the deduplication with latency on every grab, which is not the trade this host wants. This script cancels the loser after the fact instead, so grabs stay immediate.

On an `On Grab` event it reads the queue for that movie alone and removes every entry scoring strictly below the release just grabbed, with `removeFromClient=true`, `blocklist=false` and `skipRedownload=true`. `skipRedownload` matters: without it Radarr searches a replacement for the release it just superseded and the pair comes straight back. An equal score is left alone, since that may be the grab that triggered the run before its download id was known.

The cancelled release stays visible in Radarr's own history, where its `grabbed` event persists. Keeping it in SABnzbd's history as well is not possible: a queue delete writes no history entry at all - verified empirically - and Radarr masks the download client's API key as `********` on `/api/v3/downloadclient`, so no amount of credentials changes that.

## `import_stuck_items.sh` - On File Import, On Manual Interaction Required

An item that finished downloading can sit in the queue as `completed` / `importPending` for two reasons. Radarr refuses the import as `Not a Custom Format upgrade for existing movie file(s)`, which is exactly what the superseded pair produces when the better release arrives after the worse one has already imported. Or it cannot match the release name to a movie at all: a German release of an English film whose movie carries no German alternate title leaves Radarr logging `No matching movie for titles` on every queue refresh, thirty seconds apart, until a human imports it by hand.

The script sweeps those items, asks `/api/v3/manualimport` for their candidates with `filterExistingFiles=false`, and imports through the real `ManualImport` command. The movie comes from the **queue entry**, not from the candidate's own title match, so the unmatched release imports as well. `Not a Custom Format upgrade` is the only rejection it clears; anything else - a sample, an unparseable name - stays refused. Before it replaces an existing file it compares scores and acts only on a strict upgrade, so a worse candidate never downgrades the library.

`--dry-run` reports what it would do and calls nothing.

## Install

Settings > Connect > Add > Custom Script, once per script:

| Script | Path | Triggers |
| --- | --- | --- |
| `supersede_queue.sh` | `/config/scripts/tools/supersede_queue.sh` | On Grab |
| `import_stuck_items.sh` | `/config/scripts/tools/import_stuck_items.sh` | On File Import, On Manual Interaction Required |

`On Manual Interaction Required` is not optional cover: a title-match failure raises no import event at all, so without it the stuck item that most needs the sweep never triggers one. Verified on 2026-08-28 - a real `completed` / `importPending` item produced no `On File Import` event.

Both exit clean on Radarr's `Test` event, so the connection test passes without touching anything. Output goes to Radarr's own log.

`import_stuck_items.sh` also runs standalone, which is the fallback if an item gets stuck without any event to trigger on:

```sh
docker exec radarr /config/scripts/tools/import_stuck_items.sh --dry-run
```

## Tests

No Radarr required - a fake `curl` serves fixture responses and records every request:

```sh
bash stacks/radarr/scripts/tools/tests/test_supersede_queue.sh
bash stacks/radarr/scripts/tools/tests/test_import_stuck_items.sh
```
