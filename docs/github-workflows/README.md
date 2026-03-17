# GitHub Workflow Docs

This folder documents the GitHub automation used in this repository.

The workflow files stay at the standard GitHub paths so you can review the
real file names and locations. In the published repository, those files are
included as disabled reference examples. Review and adapt them before enabling
them in another deployment.

## Renovate

Renovate is configured through
[`../../.github/workflows/renovate.yaml`](../../.github/workflows/renovate.yaml)
and a repository-local `config.js`.

Renovate scans the repository for Docker image references in `compose.yaml`
files and keeps pinned tags and digests current.
It can also apply repository-specific rules such as package matching,
automerge behavior, scheduling, and branch handling.

In this repository, Renovate is used for the `image: repo:tag@sha256:...`
pattern that the stack definitions follow.

The published `renovate.yaml` keeps the same path and file name, but its
triggers are intentionally set to a non-matching branch and the job is guarded
with `if: ${{ false }}` so it remains a reference copy only.
