# SABnzbd + Gluetun

> Usenet download stack paired with VPN routing and recovery automation hooks

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `sabnzbd`. For the encrypted deployment workflow with SOPS, age, File Watcher, and Komodo, see [`docs/sops-age-komodo.md`](../../docs/sops-age-komodo.md).

## Services

- `gluetun`
- `sabnzbd`

## Upstream

### `gluetun`

- Website: [https://github.com/qdm12/gluetun](https://github.com/qdm12/gluetun)
- GitHub: [https://github.com/qdm12/gluetun](https://github.com/qdm12/gluetun)

### `sabnzbd`

- Website: [https://sabnzbd.org/](https://sabnzbd.org/)
- GitHub: [https://github.com/sabnzbd/sabnzbd](https://github.com/sabnzbd/sabnzbd)

## Scripts

- [Download Speed Monitor and Recovery Script](./scripts/monitor_sab_speed/README.md): Host-side throughput monitoring with controlled recovery paths for slow SABnzbd runs.
- [ISO Extractor Post-Processing Script](./scripts/extract_iso/README.md): SABnzbd post-processing helper that extracts ISO payloads and removes the source image afterwards.
- [Delete Items From History Scripts](./scripts/delete_item_from_history/README.md): Queue-based cleanup helpers for selected SABnzbd history categories.

## Komodo Notes

This stack needs one additional Komodo consideration because `sabnzbd` depends
on the `gluetun` container.

If `gluetun` gets redeployed on its own, the old container disappears and
`sabnzbd` can still remain attached to that no longer existing container
instance. In practice, that means a `gluetun` update is not complete unless
`sabnzbd` is redeployed as well.

For that reason, configure the stack in Komodo so a `gluetun` update forces a
redeploy of `sabnzbd` too.

### Example service dependency configuration

![Example Komodo service selection for the SABnzbd stack](./assets/01.png)

### Example redeploy requirement

![Example Komodo redeploy requirement for the SABnzbd stack](./assets/02.png)
