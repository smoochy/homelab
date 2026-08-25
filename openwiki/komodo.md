---
type: Tool
title: Komodo
description: Information about the Komodo deployment tool used in this repository for Docker Compose stacks.
tags: [komodo, deployment, docker-compose]
---

# Komodo

[Komodo](https://github.com/simplyecho/komodo) is a deployment tool for Docker Compose stacks that supports environment variable substitution, encrypted secrets (via SOPS/age), and a consistent workflow for rendering and deploying services.

## Role in This Repository

In this homelab repository, Komodo is used to:

- Render `compose.yaml` files with environment variables from `.env` or `.env.enc`.
- Deploy stacks using Docker Compose under the hood.
- Provide a uniform command interface across all stacks.

Komodo is not stored in this repository; it is expected to be installed separately.

## Installation

Refer to the [Komodo GitHub repository](https://github.com/simplyecho/komodo) for installation instructions.

Typically, you can install it via:

```bash
# Using Go
go install github.com/simplyecho/komodo@latest

# Or download a release binary from the GitHub releases page.
```

## Usage

Komodo is invoked with a `-f` flag pointing to a `compose.yaml` file, similar to `docker-compose`.

Example:

```bash
komodo -f stacks/<stack>/compose.yaml up -d
```

Komodo will automatically look for `.env` or `.env.enc` in the same directory as the compose file and use them for variable substitution.

If `.env.enc` is present, Komodo decrypts it using the age key (via the `SOPS_AGE_KEY_FILE` environment variable or default location) before substitution.

## Why Komodo?

The repository chose Komodo for:

- Built-in SOPS/age support for encrypted environment files.
- Consistent behavior across stacks.
- Simplicity: it focuses on rendering and deploying compose files without extra complexity.

## Source

- Official repository: https://github.com/simplyecho/komodo
- Workflow description: See [Deployment Workflow](/openwiki/deployment.md) and [SOPS & age Encryption](/openwiki/sops-age.md).
- Example usage: Check any stack's README for specific komodo commands (though the generic command above works for all).