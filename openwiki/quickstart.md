---
type: Documentation Hub
title: Homelab Wiki
description: Central documentation for the Docker-based homelab repository, covering stacks, deployment workflows, SOPS/age encryption, and operational guidance.
tags: [homelab, docker, komodo, sops, age]
---

# Homelab Wiki

This wiki documents the structure, conventions, and operational workflows of the Docker-based homelab repository. It is organized to help users and future agents understand how stacks are defined, deployed, and maintained.

## Navigation

- [**Stacks**](/openwiki/stacks.md) – Overview of all services (stacks) in the `stacks/` directory, their purpose, and common patterns.
- [**Deployment Workflow**](/openwiki/deployment.md) – How to deploy stacks using Komodo, including SOPS/age encrypted environment handling.
- [**SOPS & age Encryption**](/openwiki/sops-age.md) – Details on the encryption workflow, file watcher setup, and key management.
- [**Komodo**](/openwiki/komodo.md) – Information about the Komodo deployment tool used in this repository.
- [**Operational Scripts**](/openwiki/scripts.md) – Helper scripts bundled with certain stacks for maintenance and automation.
- [**Supplementary Documentation**](/openwiki/docs.md) – Additional guides and references stored in the `docs/` directory.

## Getting Started

To use this repository as a base for your own homelab:

1. Clone the repository.
2. Copy `.env.example` files from desired stacks to local `.env` files (kept out of Git via `.gitignore`).
3. Configure your SOPS/age keys as described in [SOPS & age Encryption](/openwiki/sops-age.md).
4. Use Komodo to render and deploy stacks (see [Deployment Workflow](/openwiki/deployment.md)).
5. Refer to individual stack READMEs in `stacks/<stack>/README.md` for upstream links and specific configuration.

## How This Wiki Is Organized

Each major area of the repository has a dedicated wiki page that explains:

- Responsibilities and purpose
- Important files and conventions
- How to extend or modify the area
- Relevant tests or validation steps (where applicable)
- Links to source code and tests

For low-level details (e.g., exact Compose service definitions), consult the source files directly; the wiki focuses on the *why* and *how* rather than reproducing file contents.