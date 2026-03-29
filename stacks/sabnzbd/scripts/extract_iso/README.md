# SABnzbd ISO Extractor Post-Processing Script

This post-processing helper extracts `.iso` files from successful SABnzbd jobs
and removes the original ISO afterwards.

It is intended to be used as a SABnzbd post-processing script and works inside
Docker-based SABnzbd setups such as Unraid.

## Table of Contents

- [Background](#background)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Logging](#logging)
- [Transparency](#transparency)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

Some post-processing workflows end up with ISO images even though the files
inside the image are what you actually want to keep available. This script
extracts those ISO files automatically after SABnzbd finishes a successful job
and removes the original ISO afterwards.

## Features

- Detects `.iso` files inside the completed download directory
- Extracts ISO contents using `7z` or `bsdtar`
- Deletes the original ISO after successful extraction
- Provides structured logging with `[INFO]`, `[WARN]`, and `[ERROR]`
- Works with SABnzbd Docker images
- Supports SABnzbd's standard post-processing arguments
- Uses safe behavior:
  - Skips failed downloads
  - Skips jobs without ISO files
  - Aborts on extraction errors

## Requirements

Your SABnzbd Docker container must contain one of the following tools:

- `7z` (recommended, via `p7zip`)
- `bsdtar` (fallback extractor)

Most Linux-based SABnzbd images include `bsdtar` by default. If you want `7z`,
you may need to use a custom Docker image. On Unraid, the `binhex-sabnzbd`
container includes `7z`.

## Install

### 1. Map the script directory

- Host path: `/mnt/user/appdata/{Name of Container}/scripts`
- Container path: `/scripts`
- Access: Read/Write

Restart the container afterwards.

Example:

![Example configuration on Unraid](mapping_example.png)

### 2. Save the script

Save the file as:

```text
/mnt/user/appdata/{Name of Container}/scripts/extract_iso.sh
```

### 3. Convert to LF line endings

If the file was created on Windows or edited with CRLF line endings, run:

```sh
sed -i 's/\r$//' /mnt/user/appdata/{Name of Container}/scripts/extract_iso.sh
```

### 4. Make the script executable

Run:

```sh
chmod +x /mnt/user/appdata/{Name of Container}/scripts/extract_iso.sh
```

### 5. Configure SABnzbd

1. Go to `Config` -> `Folders`.
2. Set `User Script Folder` to `/scripts`.
3. Go to `Config` -> `Categories`.
4. In the `Script` column, assign the script to the category you want to
   process, for example `Default`.
5. Save the category changes.

![Assigning script to category](category.png)

## Usage

SABnzbd runs the script automatically after a successful download for any
category where `extract_iso.sh` is assigned.

## Logging

You can view the script output in SABnzbd history by expanding the relevant job.

![Logging](logging.png)

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for script-specific change history.

## Transparency

The code, documentation, and related project materials in this repository were
created and refined with AI assistance. All generated output was reviewed and
adapted before publication.

## Maintainers

- [smoochy](https://github.com/smoochy)

## Contributing

Issues and pull requests are welcome. Keep changes focused on reliable
post-processing behavior and update the setup instructions when runtime
requirements change.

## License

[MIT](../../../../LICENSE) 2026 [smoochy](https://github.com/smoochy)
