# Changelog

## 2026-03-14

### New behavior

- The Tautulli script agent now runs on `Stop` instead of `Watched`.
- Before changing anything in Radarr, the script now verifies the
  most recent completed Tautulli movie session in `tautulli.db`.
- The watched threshold is no longer configured twice. The script
  now reads `movie_watched_percent` directly from the Tautulli
  `config.ini`.
- This prevents false-positive Radarr tagging and deletion when
  Plex or the playback client briefly reports an incorrect resume
  position near the credits or end of the movie.
- Multi-session viewing is now handled safely. Stopping a movie in
  the middle triggers the script, but Radarr changes are skipped
  until the last completed session reaches the Tautulli movie
  watched percentage.
- The Tautulli script timeout was increased to give the session
  verification enough time to find the just-finished session.
- Film-related log output now includes the movie title and year,
  and watched-verification logs also retain the Plex `ratingKey`
  for easier troubleshooting.
- New queue entries in `radarr_movie.pending.json` now also store
  the movie year so delayed deletion logs can use the same
  `Title (Year)` format.
- The README examples were updated to reflect the corrected log
  output and queue payload format.
- The script README now links directly to this changelog so
  behavior changes stay discoverable.

## 2026-03-08

### Previous behavior

- The script applied the `watched` tag and started a delayed
  `sleep ... && DELETE` process inside the running Tautulli
  container.
- If the Tautulli container was restarted before the delay expired,
  the pending deletion was lost.
- Configuration values were hardcoded directly in the script.

### Current behavior

- The script applies the `watched` tag and stores delayed deletions
  in `radarr_movie.pending.json`.
- Queue entries survive Tautulli container restarts and are
  processed on later runs.
- A dedicated `--run-pending` mode allows queue processing without
  a playback event.
- Configuration is provided through environment variables injected
  into the Tautulli container.
- The script can also run on the Unraid host without the
  `requests` package by using the Python standard library
  fallback.
