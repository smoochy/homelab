# Changelog

## 2026-03-14

### Documentation

- Added a dedicated script-level changelog so future behavior and setup changes
  can be tracked in one place.
- Linked the script README to this changelog for easier change visibility.

### Current behavior snapshot

- `extract_iso.sh` is intended to run as a SABnzbd post-processing script.
- The script is documented to run from a mapped `/scripts` directory inside the
  container.
- The current README covers line-ending conversion, executable permissions, and
  category-based SABnzbd assignment.
