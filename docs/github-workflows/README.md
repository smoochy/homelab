# GitHub Workflow Docs

This folder documents the GitHub automation used in this repository.

The workflow files stay at the standard GitHub paths so you can review the
real file names and locations. In the published repository, those files are
included as disabled reference examples. Review and adapt them before enabling
them in another deployment.

## Dependabot

Dependabot is configured through
[`../../.github/dependabot.yml`](../../.github/dependabot.yml).

Its job in this repository is limited to GitHub Actions dependency updates. It
checks the workflow files under `.github/` on a daily schedule and proposes
updates when a newer action version is available.

The published `dependabot.yml` keeps the same path and file name, but version
updates are intentionally disabled there with `open-pull-requests-limit: 0`.

That means:

- action references such as `actions/checkout` stay current
- update PRs are created by GitHub itself
- the config stays small because it only targets the `github-actions` ecosystem

## Renovate

Renovate is configured through
[`../../.github/workflows/renovate.yaml`](../../.github/workflows/renovate.yaml)
and a repository-local `config.js`.

Its role is broader than Dependabot. Renovate scans the repository for Docker
image references in `compose.yaml` files and keeps pinned tags and digests current.
It can also apply repository-specific rules such as package matching,
automerge behavior, scheduling, and branch handling.

In this repository, Renovate is used for the `image: repo:tag@sha256:...`
pattern that the stack definitions follow.

The published `renovate.yaml` keeps the same path and file name, but its
triggers are intentionally set to a non-matching branch and the job is guarded
with `if: ${{ false }}` so it remains a reference copy only.

## Why Both Exist

- Dependabot keeps GitHub Action versions current.
- Renovate keeps Docker image references current and supports richer rules.

The two tools solve different update problems, so documenting both in one place
helps keep the repository easier to understand.
