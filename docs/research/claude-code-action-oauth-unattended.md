# claude_code_oauth_token in unattended GitHub Actions runs

## Question

Does a `claude_code_oauth_token` secret actually authenticate `anthropics/claude-code-action` in a fully unattended GitHub Actions run - one triggered by `repository_dispatch` or `schedule`, with no interactive login and no `ANTHROPIC_API_KEY`?

## Verdict

Conditional, and the condition is operationally hostile: a Claude Pro subscription can mint a working token with `claude setup-token` and the action accepts it on any trigger including `schedule` and `repository_dispatch`, but the token is short-lived with no refresh mechanism in the action, and an expired token fails silently as a green workflow run - which is precisely the failure mode an unattended release watcher cannot tolerate.

## Findings

### 1. How the token is minted

The action's setup guide states the credential explicitly: "Or `CLAUDE_CODE_OAUTH_TOKEN` for OAuth token authentication (Pro and Max users can generate this by running `claude setup-token` locally)" (`docs/setup.md`, repeated verbatim in the repository-secret instructions later in the same file). The token is an OAuth access token in the `sk-ant-oat01-*` form, as quoted in several issue titles. It is minted interactively on a developer machine and then pasted into GitHub as a repository secret; there is no server-side or CI-side minting path.

The action exposes it as the input `claude_code_oauth_token`, described in `action.yml` as "Claude Code OAuth token (alternative to anthropic_api_key)". The input is first-class and supported, not a legacy accident.

### 2. Is a Pro subscription sufficient

Yes for the auth handshake itself: the documentation names Pro and Max users as the audience for `claude setup-token`. Notably the action's README no longer lists subscription OAuth among its headline authentication methods - it advertises "Anthropic direct API (API key or workload identity federation), Amazon Bedrock, Google Vertex AI, and Microsoft Foundry" - which suggests subscription OAuth is supported but is not the path the maintainers steer people toward.

There is also evidence that a setup-token session carries a reduced entitlement profile compared to an interactive login on the same account. `anthropics/claude-code` issue 83900 reports "Setup-token auth silently downgrades Fable 5 to Sonnet 5 (subscriptionType missing from token profile)", and issues 73350 and 79360 report the same class of problem: setup-token sessions reporting `hasAvailableSubscription: false` and gating the top-tier model behind a usage-credits dialog. This matters for the design only if the workflow needs a specific model tier; it does not block authentication as such.

### 3. Token lifetime and expiry behavior

This is the load-bearing finding. `anthropics/claude-code-action` issue 727, "Support refresh tokens for Claude Max subscribers in GitHub Actions", states the situation plainly: "The current OAuth flow produces tokens that expire in approximately 1 day, making it impractical for CI/CD use", and lists as a gap that "There is no `claude_code_refresh_token` input to automatically refresh expired tokens". The issue is still open. The docs do not state a lifetime figure anywhere, so the roughly one day number is a user report rather than an official guarantee - but no official source contradicts it, and no source documents a long-lived variant.

Worse than the short lifetime is how expiry manifests. Issue 1501, "Expired OAuth token produces a silent 2-second 'Claude finished' instead of an auth error", reports that with an expired token "the workflow run concludes `success`", the tracking comment reads "Claude finished @user's task in 2s" with no content, and "the only warning in the log is an unrelated cache-scope message ... that actively misdirects debugging". The reporter spent an afternoon diagnosing it. That issue is also still open.

Related open reports reinforce that this credential path is the flaky one: issues 1613 and 1614 (`claude_code_oauth_token` from `claude setup-token` rejected with 401 in the action while the same account authenticates fine locally), issue 1386 (OAuth-token auth hangs indefinitely with zero output on a GitHub-hosted runner), issue 1316 (`sk-ant-oat01-*` fails with "Header 14 invalid value"), and issue 1281 (intermittent `validateHeaders` failure with Max-plan OAuth tokens). In the CLI repo, issue 84770 reports the token "periodically becomes invalid requiring re-authentication".

### 4. Triggers other than issue_comment and pull_request

Supported. The action's own solutions guide ships a "Scheduled Maintenance" pattern using `schedule:` with a cron expression plus `workflow_dispatch:` for manual runs, and names the key configuration as "`schedule:` for automated runs" and "`workflow_dispatch:` for manual triggering". The mechanism is the `prompt` input: `action.yml` documents it as "Instructions for Claude. Can be a direct prompt or custom template", and the README describes automatic mode detection - "whether responding to @claude mentions, issue assignments, or executing automation tasks with explicit prompts". Providing `prompt` selects the automation mode that needs no comment or PR to react to.

The documentation carries no `repository_dispatch` example specifically, but nothing in the trigger handling is documented as restricting it, and `repository_dispatch` is structurally equivalent to `schedule` and `workflow_dispatch` for this purpose: no issue or PR context, prompt supplied inline. Treat it as very likely fine but unproven by any primary source.

### 5. Can the action open a pull request itself, and with which permissions

Yes. The action has first-class branch support: `action.yml` exposes `base_branch` ("The branch to use as the base/source when creating new branches"), `branch_prefix` (default `claude/`), and `branch_name_template`. The scheduled-maintenance example in the solutions guide grants `contents: write`. Opening a pull request additionally needs `pull-requests: write`. Where the action authenticates to GitHub via the official Claude GitHub App rather than `GITHUB_TOKEN`, `id-token: write` is also required - `docs/setup.md` notes that "The default GitHub App authentication path already requires this permission".

Two operational traps worth carrying into the design: issue 1509 reports that a revoked app token is left in the origin remote URL, breaking later git operations in the same job, and issue 1236 reports the action failing when `actions/checkout` uses `persist-credentials: false` - which is exactly what `codebase-memory-mcp-vscode`'s existing `ci.yaml` does on every checkout step.

### 6. Known limitations on unattended use

Beyond the silent-expiry problem, the action exposes no subscription rate-limit status: issue 1518 is an open feature request to "Expose subscription rate-limit status (5h / weekly utilization) as an action output". An unattended run therefore cannot tell in advance whether it has budget, and a subscription-limit refusal is not distinguishable from other empty outcomes without parsing logs.

## Open questions

Whether the roughly one day lifetime from issue 727 still holds, or whether `claude setup-token` now mints something longer-lived. No primary source documents any lifetime at all, so this can only be settled empirically by minting a token, recording the date, and observing when it stops working.

Whether `repository_dispatch` is explicitly supported, since the docs demonstrate only `schedule` and `workflow_dispatch`.

Whether workload identity federation is reachable without an API-key-billed organization. It is the maintainers' recommended answer to "do not store a static credential", requires `id-token: write` plus a federation rule ID and an Anthropic organization UUID, and would sidestep the entire expiry problem - but it presumes an Anthropic organization, which a Pro subscription may not provide.

## Sources

- [anthropics/claude-code-action docs/setup.md](https://github.com/anthropics/claude-code-action/blob/main/docs/setup.md)
- [anthropics/claude-code-action action.yml](https://github.com/anthropics/claude-code-action/blob/main/action.yml)
- [anthropics/claude-code-action docs/solutions.md](https://github.com/anthropics/claude-code-action/blob/main/docs/solutions.md)
- [anthropics/claude-code-action docs/usage.md](https://github.com/anthropics/claude-code-action/blob/main/docs/usage.md)
- [Issue 727: Support refresh tokens for Claude Max subscribers in GitHub Actions](https://github.com/anthropics/claude-code-action/issues/727)
- [Issue 1501: Expired OAuth token produces a silent 2-second "Claude finished" instead of an auth error](https://github.com/anthropics/claude-code-action/issues/1501)
- [Issue 1386: OAuth-token auth hangs indefinitely on GitHub-hosted runner](https://github.com/anthropics/claude-code-action/issues/1386)
- [Issue 1614: claude_code_oauth_token rejected with 401 in the action](https://github.com/anthropics/claude-code-action/issues/1614)
- [Issue 1509: Revoked app token left in the origin remote URL](https://github.com/anthropics/claude-code-action/issues/1509)
- [Issue 1236: claude-code-action fails when actions/checkout uses persist-credentials: false](https://github.com/anthropics/claude-code-action/issues/1236)
- [Issue 1518: Expose subscription rate-limit status as an action output](https://github.com/anthropics/claude-code-action/issues/1518)
- [anthropics/claude-code issue 83900: Setup-token auth silently downgrades model tier](https://github.com/anthropics/claude-code/issues/83900)
- [anthropics/claude-code issue 84770: OAuth token periodically becomes invalid](https://github.com/anthropics/claude-code/issues/84770)
