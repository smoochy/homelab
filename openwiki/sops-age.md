---
type: Guide
title: SOPS & age Encryption
description: Details on the encryption workflow using SOPS and age, including file watcher setup and key management.
tags: [sops, age, encryption, komodo, environment]
---

# SOPS & age Encryption

This repository uses [SOPS](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age) to encrypt environment files (`.env`) so that they can be safely stored in Git. The decryption happens at deployment time via Komodo.

## Overview

The workflow is:

1. You edit a local `.env` file (based on `.env.example` from a stack).
2. A file watcher (via VS Code extension) automatically encrypts `.env` to `.env.enc` on save.
3. Git tracks `.env.enc` (the encrypted file), while `.env` is ignored (via `.gitignore`).
4. At deployment time, Komodo decrypts `.env.enc` using the age key and uses the decrypted values for environment variable substitution in `compose.yaml`.

This ensures that secrets never appear in plain text in the repository.

## Local File Watcher Setup

The setup expects the VS Code extension [File Watcher](https://marketplace.visualstudio.com/items?itemName=appulate.filewatcher) and two PowerShell scripts in `.vscode/.scripts/`:

- `encrypt.ps1`
- `decrypt.ps1`

These scripts handle the encryption and decryption using `sops` and `age`, setting the appropriate `SOPS_AGE_KEY_FILE` for the operating system.

### Installing Tools

#### macOS

```sh
brew install sops
brew install age
brew install --cask powershell
```

#### Windows (using winget)

```powershell
winget install --id Microsoft.PowerShell --source winget
winget install --id Mozilla.SOPS --source winget
winget install --id FiloSottile.age --source winget
```

### Setting Up the age Key

Generate an age key pair and save the public key to `~/.config/sops/age/keys.txt` (or the equivalent Windows path).

Verify the setup:

```sh
age-keygen -y ~/.config/sops/age/keys.txt
```

This should output the age public key (starting with `age1...`).

### VS Code Configuration

Add the following to your global VS Code user settings (`settings.json`):

```json
"filewatcher.commands": [
  {
    "cmd": "pwsh -NoProfile -File \"${workspaceRoot}/.vscode/.scripts/encrypt.ps1\" -InputFile \"${file}\"",
    "event": "onFileChange",
    "isAsync": true,
    "match": "(^|[\\\\/])\\.env$"
  },
  {
    "cmd": "pwsh -NoProfile -File \"${workspaceRoot}/.vscode/.scripts/decrypt.ps1\" -InputFile \"${file}\"",
    "event": "onFileChange",
    "isAsync": true,
    "match": "\\.env\\.enc$"
  }
]
```

### How It Works

- Editing `.env` triggers encryption to `.env.enc`.
- Editing `.env.enc` triggers decryption to a temporary `.env` for inspection.
- Git only sees `.env.enc` (encrypted), keeping secrets safe.

The encrypt script refuses to encrypt a `.env` file that contains any empty values (to avoid bare `KEY=` lines). Instead, it comments out the line. If encryption fails, check that the file watcher commands are still set and that there are no empty values.

## Key Material

The age identity (private key) must be available on the machine performing encryption/decryption and on any machine deploying with Komodo (for decryption).

- On macOS/Linux: `~/.config/sops/age/keys.txt`
- On Windows: `$env:USERPROFILE\.config\sops\age\keys.txt`

## Source

- Documentation: `/docs/sops-age-komodo.md`
- Scripts: `/vscode/.scripts/encrypt.ps1` and `/vscode/.scripts/decrypt.ps1` (not in the root; they are expected in the workspace)
- The `.gitignore` should already ignore `.env` and track `.env.enc`.