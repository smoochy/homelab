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

The repository now owns the effective PR wait timers instead of relying on
Renovate `stability-days`:

- `repo/pr-head-age-anchor` records the first-seen timestamp for the current
  PR head SHA
- `renovate/docker-pr-age-24h` turns green once that current head SHA has
  aged at least 24 hours
- head-SHA changes reset both timers because a new head commit receives a new
  anchor
- metadata-only PR edits do not reset the timers

The `pr-age-gate` workflow refreshes those statuses on PR events and on a
schedule. The `timed-pr-automerge` workflow evaluates all non-preview PRs and
merges them only when the current head SHA is at least 5 days old, the PR is
mergeable, all merge-relevant checks are green, and no human review blocker
remains.

`pr-age-gate` concurrency is isolated per PR for `pull_request` runs and per
ref for scheduled or manual runs so parallel Renovate PRs do not cancel each
other's check runs.

The published `renovate.yaml` keeps the same path and file name, but its
triggers are intentionally set to a non-matching branch and the job is guarded
with `if: ${{ false }}` so it remains a reference copy only.

## Public Mirror Preview and Publish

The public mirror automation now has three behaviors:

- image-only compose updates can still publish directly
- general public-export changes still use the shared technical preview PR plus
  manual `/publish`
- the isolated Traefik env-sync path creates its own technical preview PR and
  then auto-publishes it immediately

That Traefik-specific path is limited to pushes that only update
`stacks/traefik/.env.enc` and `stacks/traefik/.env.example`. It uses its own
preview branches so it never publishes unrelated pending changes from the
general public preview flow.

## Metabase

Metabase uses a narrower flow than the rest of the Renovate-managed images.

- Renovate raises a normal PR for `metabase/metabase` updates instead of using
  branch automerge.
- That PR stays bot-driven and is not assigned to `smoochy`.
- A dedicated GitHub Actions check validates that the PR is a Metabase-only
  image/digest update and that the public export still builds.
- The repository-owned `renovate/docker-pr-age-24h` status enforces the rolling
  24-hour wait on the current PR head SHA.
- The Renovate workflow explicitly dispatches that validation because PR events
  created by the workflow token do not automatically fan out into another
  workflow run.
- Once the check is green, Renovate merges the PR on its next run.
- After merge, image-only Metabase updates publish directly to the public repo
  even if the shared public preview PR is already open for unrelated changes.

See [`./metabase/README.md`](./metabase/README.md) for the detailed flow,
validation rules, and test scenarios.
