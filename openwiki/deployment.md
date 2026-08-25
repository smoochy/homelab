---
type: Workflow
title: Deployment Workflow
description: How to deploy stacks using Komodo, including SOPS/age encrypted environment handling.
tags: [deployment, komodo, docker-compose, sops, age]
---

# Deployment Workflow

This repository uses [Komodo](https://github.com/simplyecho/komodo) as the deployment tool for Docker Compose stacks. Komodo provides a consistent workflow for rendering and deploying stacks with environment variable substitution and encrypted secrets.

## Overview

The typical deployment flow is:

1. **Environment Preparation**: Edit a local `.env` file (based on `.env.example` from a stack).
2. **Encryption (Optional but Recommended)**: Use SOPS/age to encrypt `.env` to `.env.enc` for safe storage in Git.
3. **Rendering**: Komodo reads `.env.enc` (or `.env` if not encrypted) and renders the `compose.yaml` with environment variables.
4. **Deployment**: Komodo deploys the rendered compose file via Docker Compose.

## Using Komodo

Komodo is invoked via the `komodo` command (available if you have it installed; see [Komodo](/openwiki/komodo.md) for installation).

### Basic Usage

To deploy a stack:

```bash
komodo -f stacks/<stack>/compose.yaml up -d
```

Komodo will automatically look for `.env` or `.env.enc` in the same directory as the `compose.yaml` file.

### Encryption Handling

If Komodo finds `.env.enc`, it will decrypt it using the age key specified by the `SOPS_AGE_KEY_FILE` environment variable (or the default location) and use the decrypted values for substitution.

If only `.env` is present, Komodo uses it directly.

## Local Development Without Encryption

For local testing, you can skip encryption and use a plain `.env` file. Komodo will still work.

## Automation with Scripts

Some stacks include helper scripts in their `scripts/` directory. These are typically invoked after deployment or as part of maintenance routines. See [Operational Scripts](/openwiki/scripts.md) for more.

## Validation

After deployment, you can verify that services are running with:

```bash
docker ps
```

Or check the logs:

```bash
komodo -f stacks/<stack>/compose.yaml logs -f
```

## Source

- Komodo configuration: Not stored in this repo; Komodo is an external tool.
- Workflow description: Based on the repository's README and the SOPS/age documentation.
- Example usage: See individual stack READMEs for specific komodo commands (if any).