# Changelog

## 2026-04-08

### Queue path hardening

- Prefer the shared SABnzbd config directory queue before the script directory.
- Prevent hook and worker drift by resolving the same shared queue location on both sides.
- Fail with a clear error when no writable shared queue path is available.

## 2026-03-14

### Initial release

- First repository release of `delete_item_from_history`.
- Added:
  - `delete_item.sh`
  - `delete_items_worker.sh`
  - `README.md`
  - `CHANGELOG.md`
- Setup, usage, and behavior are documented in the script README.
