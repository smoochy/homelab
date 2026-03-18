# Metabase Renovate Flow

This document describes the dedicated Renovate and public-sync flow for
`metabase/metabase` as used by the CrowdSec dashboard in
[`../../../crowdsec`](../../../crowdsec/).

## Goal

Metabase updates for the CrowdSec dashboard stack in
[`../../../crowdsec`](../../../crowdsec/) should behave differently from the
rest of the Docker updates in this repository:

- Renovate creates a PR instead of using branch automerge.
- The PR remains bot-driven and does not assign or request review from
  `smoochy`.
- A dedicated check verifies that the PR is only the expected Metabase image
  update and that the public export still builds.
- Once that check is green, Renovate merges the PR on the next Renovate run.
- After merge, the public mirror receives a direct commit on `main` without
  going through the shared preview PR, even if that preview PR is already open
  for unrelated changes.

## Flow

1. Renovate detects a new `metabase/metabase` tag or digest and creates a PR.
2. The `metabase-renovate-validate` workflow runs on that PR.
3. The workflow validates:
   - only `crowdsec/compose.yaml` changed
   - every changed image line is a `metabase/metabase` image line
   - the sanitized public export still builds successfully
4. Renovate observes the green check on a later run and merges the PR.
5. The merge to private `main` triggers `public-preview`.
6. If the merge is a Metabase-only image update, the public export is committed
   directly to the public repo `main`.

## Validation Scope

The dedicated check is intentionally narrow. It validates the expected Metabase
PR shape instead of trying to become a general Renovate CI framework.

- The check targets Renovate PRs that touch `crowdsec/compose.yaml`.
- It fails if the diff contains non-image changes or non-Metabase image changes.
- It reuses the same export scripts that power the public mirror workflow so
  the merge gate reflects the real publish path.

## Notifications

The silent behavior only applies to Metabase automation inside this repository.

- No Metabase-specific assignee or reviewer request should target `smoochy`.
- Metabase-specific Renovate notification comments are suppressed where the
  Renovate configuration supports it.
- Personal GitHub watch or email settings are not changed by this repository.
- Other Renovate PRs keep their existing notification behavior.

## Test Matrix

- PR creation: Renovate raises a normal PR for Metabase.
- Silent PR: the PR is bot-authored and not assigned to `smoochy`.
- Validation success: the dedicated check passes for a valid image/digest-only
  Metabase update.
- Automerge: Renovate merges the PR on the next run after the check turns
  green.
- Public sync: the merge creates exactly one commit on the public repo `main`.
- Preview conflict: the direct public publish still happens when the shared
  `public-sync-preview` PR is already open.
- Negative case: non-Metabase changes continue to use the shared preview PR
  flow.
