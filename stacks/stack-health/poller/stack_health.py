"""Stack health poller for the homelab (homelab issues #883, #884, #1005).

Komodo reports a deploy, not a stack. Issue #967 is the proof: a deploy was
recorded as `success: true` over a qBittorrent stack whose containers were gone,
and nothing said a word. A green deploy is a statement about the past; this
poller makes a statement about now.

What it watches, per round:

- `ListStacks` is the sweep. `GetStacksSummary`, which #883 named, turned out to
  return aggregate counts only ({"total": 30, "running": 29, ...}) and cannot
  drive a per-stack decision, so the sweep is `ListStacks` instead.
- `ListStackServices` per stack gives every compose service and its container. A
  service with no container at all is the #967 shape: not unhealthy, absent.
- `InspectStackContainer` is ground truth for anything that looks off. Komodo's
  cached container state is known to read green over a dead container, so no
  alert is ever raised on the list alone, and no classification is made by
  string-matching the human-readable `status` line.

- `ListRepos` is the second sweep, added for #1792. A Komodo Repo resource runs
  an `on_pull` hook, and a hook that exits non-zero fails the pull - which
  Komodo renders red and cannot alert on, because no `AlertData` variant covers
  it. Its `state` field is the whole signal, so it is polled rather than
  subscribed to.

Failing means unhealthy, missing, exited, or restart-looping - #967 had no
health status to be unhealthy, so "unhealthy" alone would have stayed silent.

Alerting is edge-triggered after the `watcher/irc-watch.sh` pattern next door:
three consecutive bad ticks before anything is said, one message on the
transition, one on recovery, a reminder every six hours while it stays broken.
Undecidable ticks - the API refused, the stack is mid-deploy - are excluded
rather than counted either way, because a probe that came back with nothing says
nothing about the stack.

Two things are deliberately muted: a stack Komodo is deploying right now plus a
grace period afterwards, and the appdata backup window, which drops a pause file
through the Uptime Kuma pre-run hook.

The poller cannot vouch for itself, so it does not try: an Uptime Kuma push
monitor is pinged at the end of every completed round and trips when this
process stops, and a Komodo that stays unreachable raises its own alert.
"""

import json
import os
import pathlib
import sys
import tempfile
import time
from datetime import datetime, timezone

import requests

KOMODO_ADDRESS = os.environ.get("KOMODO_ADDRESS", "").rstrip("/")
KOMODO_API_KEY = os.environ.get("KOMODO_API_KEY", "")
KOMODO_API_SECRET = os.environ.get("KOMODO_API_SECRET", "")
# The address the alert links to, which is the one a human can open - the API
# address is an internal LAN IP and may not be it.
KOMODO_HOST = os.environ.get("KOMODO_HOST", KOMODO_ADDRESS).rstrip("/")
APPRISE_ENDPOINT = os.environ.get("APPRISE_ENDPOINT", "")
KUMA_PUSH_URL = os.environ.get("KUMA_PUSH_URL", "")

INTERVAL_SECONDS = int(os.environ.get("STACK_HEALTH_INTERVAL_SECONDS", "60"))
FAILURES_BEFORE_ALERT = int(os.environ.get("STACK_HEALTH_FAILURES", "3"))
REPEAT_SECONDS = int(os.environ.get("STACK_HEALTH_REPEAT_SECONDS", "21600"))
DEPLOY_GRACE_SECONDS = int(os.environ.get("STACK_HEALTH_DEPLOY_GRACE_SECONDS", "300"))
# The ceiling on consecutive busy skips for one stack, at ten minutes twice the
# grace window: long enough that no single deploy reaches it, short enough that
# a stack redeployed in a loop is still looked at.
MAX_BUSY_SKIPS = int(os.environ.get("STACK_HEALTH_MAX_BUSY_SKIPS", "10"))
UNDECIDABLE_BEFORE_ALERT = int(os.environ.get("STACK_HEALTH_UNDECIDABLE_TICKS", "5"))
STATE_FILE = os.environ.get("STACK_HEALTH_STATE_FILE", "/state/stack-health.json")
PAUSE_FILE = os.environ.get("STACK_HEALTH_PAUSE_FILE", "/state/paused")
# The marker this container's own healthcheck reads. It lives in /run, in the
# writable layer, rather than beside the state file on the host bind: host state
# would survive a restart and report a dead poller as healthy.
HEARTBEAT_FILE = os.environ.get("STACK_HEALTH_HEARTBEAT_FILE", "/run/stack-health.heartbeat")
# A pause marker older than this is ignored: the backup takes hours, but not
# days, and a hook that died mid-backup must not mute the watcher for good.
PAUSE_MAX_SECONDS = int(os.environ.get("STACK_HEALTH_PAUSE_MAX_SECONDS", "21600"))
# Stacks that are expected to be down, or whose absence is somebody else's
# problem. Komodo's own template stack `_stacks` is permanently down by design.
EXCLUDE_STACKS = {
    name.strip()
    for name in os.environ.get("STACK_HEALTH_EXCLUDE_STACKS", "").split(",")
    if name.strip()
}
TIMEOUT = int(os.environ.get("STACK_HEALTH_HTTP_TIMEOUT_SECONDS", "30"))

session = requests.Session()
session.headers.update(
    {
        "x-api-key": KOMODO_API_KEY,
        "x-api-secret": KOMODO_API_SECRET,
        "content-type": "application/json",
    }
)


def log(message):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"{stamp} {message}", flush=True)


def read(request_type, params=None):
    response = session.post(
        f"{KOMODO_ADDRESS}/read",
        json={"type": request_type, "params": params or {}},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    return response.json()


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

def is_suspect(container):
    """Cheap filter over Komodo's cached view: is this worth an inspect?

    Never a verdict. The list is read for one bit only - "look closer" - so a
    stale entry can cost an inspect but can never produce an alert on its own.
    A container that is simply absent needs no inspect: there is nothing to
    inspect, and absence is already the answer.
    """
    if not container:
        return True
    if container.get("state") != "running":
        return True
    # The only thing read out of the human-readable status line, and only ever
    # to widen the suspect set, never to narrow it: a container without a
    # healthcheck carries no health suffix at all and must stay unsuspected.
    return "unhealthy" in (container.get("status") or "").lower()


def classify(inspected):
    """Verdict from `InspectStackContainer`, or None when the container is fine.

    A one-shot init container is the reason `RestartPolicy` is read here and not
    only `State`. The `*-probe-busybox` services next door copy a static busybox
    into a shared volume, exit 0 and are depended on with
    `service_completed_successfully`: exited is the finished state they are
    supposed to reach, and reading it as a failure alerted for days. Only exit 0
    under a policy that never restarts counts as finished - a non-zero exit, or
    an exit under `unless-stopped`, is still a container that should be up.
    """
    state = inspected.get("State") or {}
    if state.get("Restarting"):
        return "restart-looping"
    status = state.get("Status")
    if status != "running":
        exit_code = state.get("ExitCode")
        policy = ((inspected.get("HostConfig") or {}).get("RestartPolicy") or {}).get("Name")
        if status == "exited" and exit_code == 0 and policy in ("", "no"):
            return None
        return f"{status} (exit {exit_code})" if status == "exited" else f"{status}"
    health = (state.get("Health") or {}).get("Status")
    if health == "unhealthy":
        return "unhealthy"
    return None


# Komodo's `RepoState` (client/core/rs/src/entities/repo.rs): `Cloning`,
# `Pulling`, `Building`, `Ok`, `Failed`, `Unknown`. Only the two settled states
# are evidence. The three in-flight ones are the repo equivalent of a stack
# mid-deploy, and `Unknown` is the serde default a repo carries when Komodo has
# no verdict at all - neither of those may read as healthy by falling through a
# `!= "Failed"` test.
REPO_OK = "Ok"
REPO_FAILED = "Failed"


def repo_is_failing(info):
    """Verdict on one repo's last clone or pull, or None when undecidable."""
    state = (info or {}).get("state")
    if state == REPO_FAILED:
        return True
    if state == REPO_OK:
        return False
    return None


def short_digest(image, digest=None):
    """`repo:tag` plus `sha256:0123...` -> `repo:tag (01234567)`.

    The digest may travel inside the reference or beside it: Komodo's cached
    container view carries whichever of the two the daemon happened to record,
    and for a locally built image that is a bare image id with no repository or
    tag at all. Both halves are optional, so whatever is known is printed and a
    missing half is simply left out.

    The digest is parenthesised rather than joined with `@`, which is what a
    docker reference would use, because the body of this alert is markdown that
    Apprise hands to a Discord webhook. Apprise's Discord plugin scans a
    markdown body for mention tokens and turns any `@` followed by digits into a
    user mention, so `busybox:1.38.0-musl@654fc8fd` shipped every alert with a
    bogus `👉 <@654>` ping in front of it. Nothing in a body that goes through
    Apprise may carry a bare `@`.
    """
    reference = image or ""
    if reference.startswith("sha256:"):
        digest, reference = digest or reference, ""
    repo, _, embedded = reference.partition("@")
    digest = (digest or embedded or "").removeprefix("sha256:")[:8]
    if not repo:
        return digest or "unknown image"
    return f"{repo} ({digest})" if digest else repo


def inspect_failures(stack_name, services):
    """The failing containers of one stack, or None when undecidable.

    An inspect that errors makes the whole stack undecidable for this tick
    rather than failing: the API refusing to answer is not evidence about the
    container, and a mid-deploy stack answers exactly like this.
    """
    failures = []
    for service in services:
        container = service.get("container")
        name = (container or {}).get("name") or service.get("service")
        if not is_suspect(container):
            continue
        if not container:
            failures.append({"name": name, "reason": "missing", "image": service.get("image")})
            continue
        try:
            inspected = read(
                "InspectStackContainer",
                {"stack": stack_name, "service": service.get("service")},
            )
        except Exception as error:
            log(f"{stack_name}/{service.get('service')}: inspect failed, tick undecidable: {error}")
            return None
        reason = classify(inspected)
        if reason:
            # The reference as written in the compose file, from the inspect
            # rather than from the cached view: the cached view can hold a bare
            # image id, which names nothing a human can read.
            reference = (inspected.get("Config") or {}).get("Image") or container.get("image")
            failures.append(
                {
                    "name": name,
                    "reason": reason,
                    "image": reference,
                    "digest": inspected.get("Image"),
                }
            )
    return failures


# ---------------------------------------------------------------------------
# Deploy window
# ---------------------------------------------------------------------------

def busy_stack_ids(now):
    """Stack ids Komodo is deploying, or finished deploying inside the grace.

    Both halves are needed. Watching only in-progress updates gives zero grace
    to any deploy that starts and finishes between two ticks, which is most of
    them; the recently-completed half covers that without keeping cross-tick
    state that could go stale.
    """
    updates = read("ListUpdates", {}).get("updates") or []
    busy = set()
    for update in updates:
        target = update.get("target") or {}
        if target.get("type") != "Stack" or not target.get("id"):
            continue
        if update.get("status") != "Complete":
            busy.add(target["id"])
            continue
        start_ts = (update.get("start_ts") or 0) / 1000
        if now - start_ts < DEPLOY_GRACE_SECONDS:
            busy.add(target["id"])
    return busy


# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------

def notify(title, body, kind="warning"):
    """Best effort, exactly as in `sorter.py`: a dead notifier never stops the
    loop. The loop is the thing that must survive."""
    if not APPRISE_ENDPOINT:
        log(f"[no apprise endpoint] {title}: {body}")
        return
    try:
        requests.post(
            APPRISE_ENDPOINT,
            json={"title": title, "body": body, "type": kind, "format": "markdown"},
            timeout=10,
        )
    except Exception as error:
        log(f"apprise notify failed: {error}")


def failure_body(stack_name, stack_id, failures, duration=None):
    """One labelled block per failing container, after the upload runner.

    The stack name is already the title, so a block is headed by the container.
    Single and multi-container failures take the same form on purpose: two
    layouts for one event is what this shape exists to remove - and that
    includes the six-hourly reminder, which used to carry a bare count. A count
    reads as "the stack is down" over a stack whose named container is up and
    whose rider is the one that died, so the reminder names them too and only
    adds how long it has been going on.
    """
    # ponytail: no length bound. A Discord embed description caps at 4096 chars
    # and apprise truncates silently, which a block of ~120 chars would only
    # reach past ~30 failing containers in one stack. Bound it if a stack ever
    # gets that big.
    lines = [f"**{stack_name}** - {len(failures)} container(s) failing"]
    if duration is not None:
        lines.append(f"⏱️ Failing for: {human_duration(duration)}")
    for failure in failures:
        lines += [
            "",
            f"**{failure['name']}**",
            f"📝 Reason: {failure['reason']}",
            f"📦 Image: {short_digest(failure.get('image'), failure.get('digest'))}",
        ]
    if stack_id and KOMODO_HOST:
        lines += ["", f"[Open in Komodo]({KOMODO_HOST}/stacks/{stack_id})"]
    return "\n".join(lines)


def repo_failure_body(repo, duration=None):
    """The failing repo, in the same shape as `failure_body`'s blocks.

    A failed pull has one subject, so there is no per-container block to repeat.
    What a human needs beyond the name is which remote and branch was being
    pulled and how far behind the clone is - `cloned_hash` against `latest_hash`
    is what says "the pull never landed" rather than "the pull landed badly".
    """
    info = repo.get("info") or {}
    lines = [f"**{repo.get('name')}** - last pull failed"]
    if duration is not None:
        lines.append(f"⏱️ Failing for: {human_duration(duration)}")
    lines += [
        "",
        f"📝 Source: {info.get('repo') or 'unknown'} (branch {info.get('branch') or 'unknown'})",
        f"🔖 Cloned: {info.get('cloned_hash') or 'none'} - latest: {info.get('latest_hash') or 'unknown'}",
    ]
    if repo.get("id") and KOMODO_HOST:
        lines += ["", f"[Open in Komodo]({KOMODO_HOST}/repos/{repo['id']})"]
    return "\n".join(lines)


def human_duration(seconds):
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h {(seconds % 3600) // 60}m"


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

def load_state():
    """Anything unreadable reads as empty, following `irc-watch.sh`: assuming a
    remembered failure instead would emit a recovery for an outage that never
    happened, while this way a stack that is already broken is announced once
    more, which is the message worth having."""
    try:
        with open(STATE_FILE, encoding="utf-8") as handle:
            state = json.load(handle)
        return state if isinstance(state, dict) else {}
    except Exception:
        return {}


def save_state(state):
    """Written through a temporary file so a kill mid-write cannot leave a
    partial marker behind."""
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(f"{STATE_FILE}.tmp", "w", encoding="utf-8") as handle:
            json.dump(state, handle)
        os.replace(f"{STATE_FILE}.tmp", STATE_FILE)
    except Exception as error:
        log(f"could not persist state to {STATE_FILE}: {error}")


def paused():
    """Read fresh every tick and fail open. A false alert during the backup
    window is cheap; a missed alert because a stale pause file was cached is
    not.

    The marker expires on its own. The post-run hook removes it, but a backup
    that dies between the two hooks would otherwise mute this watcher forever -
    a permanently silent alerting path is the exact failure this poller exists
    to make impossible, so it must not be reachable by leaving a file behind.
    """
    try:
        age = time.time() - os.path.getmtime(PAUSE_FILE)
    except OSError:
        return False
    if age > PAUSE_MAX_SECONDS:
        log(f"pause marker is {human_duration(age)} old, ignoring it")
        return False
    return True


# ---------------------------------------------------------------------------
# Edge trigger
# ---------------------------------------------------------------------------

def step(entry, bad, now, decisive=False):
    """Advance one stack's state by one decidable tick, returning the alert to
    send as (kind, extra) or None.

    A three-way caller: this is only ever called for a decided tick. An
    undecidable tick must not call it at all, because `streak = 0` on a flaky
    API answer would silently discard a real outage a tick before it alerts.

    `decisive` shortens the debounce to a single tick, and only on the first bad
    tick of an outage. The debounce exists for states a container can pass
    through on its way somewhere else; `created` is not one of them, because the
    stack is only looked at once its deploy window has closed and nothing moves
    a container out of `created` but a start that is no longer coming. Scoping
    it to `streak == 1` keeps a stack that has been accumulating ticks under the
    normal rule on that rule, rather than alerting it early on a later tick.
    """
    if bad:
        entry["streak"] = entry.get("streak", 0) + 1
        if entry.get("alerted"):
            if now - entry.get("last_alert", 0) >= REPEAT_SECONDS:
                entry["last_alert"] = now
                return "repeat", now - entry.get("failing_since", now)
            return None
        if decisive and entry["streak"] == 1:
            entry["alerted"] = True
            # One tick of outage, so the streak arithmetic below would be wrong:
            # this outage started now.
            entry["failing_since"] = now
            entry["last_alert"] = now
            return "failure", None
        if entry["streak"] >= FAILURES_BEFORE_ALERT:
            entry["alerted"] = True
            # The outage started when the streak did, not when it was believed.
            entry["failing_since"] = now - (entry["streak"] - 1) * INTERVAL_SECONDS
            entry["last_alert"] = now
            return "failure", None
        return None

    was_alerted = entry.get("alerted")
    failing_since = entry.get("failing_since", now)
    # Reset in full, so a later outage alerts on its own three ticks and is not
    # held back by the previous outage's six-hour clock.
    entry.clear()
    if was_alerted:
        return "recovery", now - failing_since
    return None


# ---------------------------------------------------------------------------
# Round
# ---------------------------------------------------------------------------

def check_repos(state, now):
    """The repo half of a round (homelab issue #1792).

    A Komodo Repo resource runs an `on_pull` hook - `scripts/deliver.sh` is one
    - and a hook that exits non-zero fails the pull. Komodo records that and
    renders it red, but it cannot alert on it: `AlertData` has no variant for a
    failed `PullRepo`, and `RepoConfig` has no `failure_alert` field, so no
    subscription can be made to fire. The verdict is therefore polled out of
    `ListRepos` here, through the same debounce, state file and Discord path the
    stack sweep already owns.

    Level, not edge: a repo sits at `Failed` until its next successful pull, so
    `step` is what turns that standing level into one message on the transition,
    a reminder every six hours, and one on recovery.
    """
    repos = read("ListRepos", {})
    repo_state = state.setdefault("repos", {})
    checked = failing = 0

    for repo in repos:
        name = repo.get("name")
        if repo.get("template"):
            continue
        info = repo.get("info") or {}
        bad = repo_is_failing(info)
        if bad is None:
            log(f"repo {name}: state {info.get('state')!r}, tick undecidable")
            continue
        checked += 1
        failing += 1 if bad else 0

        entry = repo_state.setdefault(name, {})
        outcome = step(entry, bad, now)
        if not entry:
            repo_state.pop(name, None)
        if not outcome:
            continue
        kind, extra = outcome
        if kind == "failure":
            notify(
                f"🛑 stack-health: {name} pull failed",
                repo_failure_body(repo),
                "failure",
            )
        elif kind == "repeat":
            notify(
                f"⚠️ stack-health: {name} pull is still failing",
                repo_failure_body(repo, extra),
                "warning",
            )
        else:
            notify(
                f"✅ stack-health: {name} pulled successfully again",
                f"**{name}**\n⏱️ Failing for: {human_duration(extra)}",
                "success",
            )
        log(f"repo {name}: {kind}")

    log(f"repos checked={checked} failing={failing}")


def run_once(state):
    now = time.time()
    if paused():
        log("paused, skipping tick")
        return

    stacks = read("ListStacks", {})
    busy = busy_stack_ids(now)
    stack_state = state.setdefault("stacks", {})
    busy_skips = state.setdefault("busy_skips", {})
    checked = skipped = failing = 0

    for stack in stacks:
        name = stack.get("name")
        info = stack.get("info") or {}
        if stack.get("template") or name in EXCLUDE_STACKS:
            continue
        if stack.get("id") in busy:
            # The skip is bounded. `busy` re-arms from every completed update's
            # `start_ts`, so a stack redeployed faster than the grace window is
            # never looked at again, and that is how #2579 stayed silent: a
            # container left in `created` by one deploy is invisible for as long
            # as deploys keep arriving. Past the cap the stack is checked while
            # still busy, which costs a false `created` only if a deploy is both
            # still creating containers and older than the cap.
            busy_skips[name] = busy_skips.get(name, 0) + 1
            if busy_skips[name] <= MAX_BUSY_SKIPS:
                skipped += 1
                continue
        else:
            busy_skips.pop(name, None)
        try:
            services = read("ListStackServices", {"stack": name})
        except Exception as error:
            log(f"{name}: services unreadable, tick undecidable: {error}")
            continue
        failures = inspect_failures(name, services)
        if failures is None:
            continue
        checked += 1
        failing += 1 if failures else 0

        entry = stack_state.setdefault(name, {})
        created = any(failure["reason"] == "created" for failure in failures)
        outcome = step(entry, bool(failures), now, decisive=created)
        if not entry:
            stack_state.pop(name, None)
        if not outcome:
            continue
        kind, extra = outcome
        if kind == "failure":
            notify(
                f"🛑 stack-health: {name} is failing",
                failure_body(name, stack.get("id"), failures),
                "failure",
            )
        elif kind == "repeat":
            notify(
                f"⚠️ stack-health: {name} is still failing",
                failure_body(name, stack.get("id"), failures, extra),
                "warning",
            )
        else:
            notify(
                f"✅ stack-health: {name} recovered",
                f"**{name}**\n⏱️ Down for: {human_duration(extra)}",
                "success",
            )
        # `info` is only read for the log line; the verdict came from inspect.
        log(f"{name}: {kind} ({info.get('status') or 'unknown'})")

    log(f"checked={checked} failing={failing} skipped={skipped} busy={len(busy)}")
    check_repos(state, now)


def kuma_push():
    """The dead-man switch, pinged only after a round completed. Pinging at the
    top of the loop would keep the monitor green through exactly the hang it
    exists to catch."""
    if not KUMA_PUSH_URL:
        return
    try:
        requests.get(KUMA_PUSH_URL, timeout=10)
    except Exception as error:
        log(f"kuma push failed: {error}")


def heartbeat():
    """The marker this container's own healthcheck reads. Touched beside the Kuma
    push and for the same reason: after a round completed, never at the top of the
    loop, so the hang the probe exists to catch cannot keep it fresh. It stays out
    of run_once, whose early return during the backup pause window would otherwise
    let the marker go stale through every backup."""
    try:
        pathlib.Path(HEARTBEAT_FILE).touch()
    except OSError as error:
        log(f"heartbeat touch failed: {error}")


def main():
    if not KOMODO_ADDRESS:
        sys.exit("KOMODO_ADDRESS is required")
    state = load_state()
    while True:
        started = time.time()
        try:
            run_once(state)
            if state.pop("api_down", False):
                notify(
                    "✅ stack-health: Komodo API reachable again",
                    "The Komodo API answers again. Stack health is being watched.",
                    "success",
                )
            state["undecidable"] = 0
            kuma_push()
            heartbeat()
        except Exception as error:
            # Consecutive, not cumulative: sparse flakiness over days must not
            # add up to a Komodo-is-down alert.
            state["undecidable"] = state.get("undecidable", 0) + 1
            log(f"round failed ({state['undecidable']}): {type(error).__name__}: {error}")
            if state["undecidable"] >= UNDECIDABLE_BEFORE_ALERT and not state.get("api_down"):
                state["api_down"] = True
                notify(
                    "⚠️ stack-health: Komodo API unreachable",
                    f"The Komodo API has not answered for {state['undecidable']} rounds "
                    f"({type(error).__name__}: {error}). No stack and no repo is being "
                    "watched right now.",
                    "warning",
                )
        save_state(state)
        # Sleep the remainder of the interval rather than the whole of it. A
        # round costs a second or two, so sleeping the full interval afterwards
        # makes every tick land a little later than the last, and the push
        # monitor watching from outside checks on a fixed schedule: every
        # second window then finds no new heartbeat and reads pending. The
        # floor keeps the loop from spinning if a round ever outlasts the
        # interval, and the `failing_since` arithmetic assumes evenly spaced
        # ticks, which this is what makes true.
        time.sleep(max(1.0, INTERVAL_SECONDS - (time.time() - started)))


def _self_check():
    """The classifier and the edge trigger are the only real logic here."""
    def inspect(state, policy="unless-stopped"):
        return {"State": state, "HostConfig": {"RestartPolicy": {"Name": policy}}}

    assert classify(inspect({"Status": "running", "Health": {"Status": "healthy"}})) is None
    assert classify(inspect({"Status": "running"})) is None  # no healthcheck is not a failure
    assert classify(inspect({"Status": "running", "Health": {"Status": "unhealthy"}})) == "unhealthy"
    assert classify(inspect({"Status": "exited", "ExitCode": 137})) == "exited (exit 137)"
    assert classify(inspect({"Status": "running", "Restarting": True})) == "restart-looping"
    # A one-shot init container that did its job and stopped. Only this exact
    # shape is excused: the same exit under a restarting policy, and any
    # non-zero exit, remain failures.
    finished = {"Status": "exited", "ExitCode": 0}
    assert classify(inspect(finished, "no")) is None
    assert classify(inspect(finished, "")) is None
    assert classify(inspect(finished)) == "exited (exit 0)"
    assert classify(inspect({"Status": "exited", "ExitCode": 1}, "no")) == "exited (exit 1)"
    # No `HostConfig` at all is not evidence of a one-shot container.
    assert classify({"State": finished}) == "exited (exit 0)"

    assert is_suspect(None) is True
    assert is_suspect({"state": "exited", "status": "Exited (1)"}) is True
    assert is_suspect({"state": "running", "status": "Up 3 days"}) is False
    assert is_suspect({"state": "running", "status": "Up 3 days (unhealthy)"}) is True
    assert is_suspect({"state": "running", "status": "Up 3 days (healthy)"}) is False

    # Three bad ticks alert once, and only once.
    entry, now = {}, 1000.0
    assert step(entry, True, now) is None
    assert step(entry, True, now + 60) is None
    assert step(entry, True, now + 120)[0] == "failure"
    assert step(entry, True, now + 180) is None
    # The reminder fires on the repeat clock and reports the whole outage.
    kind, age = step(entry, True, now + 120 + REPEAT_SECONDS)
    assert kind == "repeat" and age >= REPEAT_SECONDS, (kind, age)
    # Recovery reports from the first bad tick, not from the alert.
    kind, outage = step(entry, False, now + 120 + REPEAT_SECONDS + 60)
    assert kind == "recovery" and outage >= REPEAT_SECONDS + 180, (kind, outage)
    assert entry == {}, entry
    # A recovered stack that breaks again waits out its own three ticks.
    assert step(entry, True, now + 100000) is None

    # A stack that goes bad once and recovers never alerts at all.
    entry = {}
    assert step(entry, True, now) is None
    assert step(entry, False, now + 60) is None

    # A container left in `created` alerts on its first decidable tick, and the
    # outage it reports is that tick rather than two ticks that never happened.
    entry = {}
    kind, extra = step(entry, True, now, decisive=True)
    assert (kind, extra) == ("failure", None), (kind, extra)
    assert entry["failing_since"] == now, entry
    assert step(entry, True, now + 60, decisive=True) is None
    kind, outage = step(entry, False, now + 120, decisive=True)
    assert kind == "recovery" and outage == 120, (kind, outage)
    # A stack already accumulating ticks under the normal rule keeps it: the
    # short cut is the first tick of an outage, not every tick carrying the
    # reason.
    entry = {}
    assert step(entry, True, now) is None
    assert step(entry, True, now + 60, decisive=True) is None
    assert step(entry, True, now + 120, decisive=True)[0] == "failure"
    # `classify` produces exactly the reason the short cut keys on.
    assert classify(inspect({"Status": "created", "ExitCode": 0})) == "created"

    # Only the two settled repo states are evidence. Every in-flight state and
    # the `Unknown` default must stay undecidable rather than read as healthy,
    # which is the one way this predicate can fail silently.
    assert repo_is_failing({"state": "Failed"}) is True
    assert repo_is_failing({"state": "Ok"}) is False
    for state_name in ("Cloning", "Pulling", "Building", "Unknown"):
        assert repo_is_failing({"state": state_name}) is None, state_name
    assert repo_is_failing({}) is None
    assert repo_is_failing(None) is None

    repo = {
        "id": "abc",
        "name": "qbittorrent-scripts",
        "info": {
            "state": "Failed",
            "repo": "smoochy/homelab",
            "branch": "main",
            "cloned_hash": "85f7052",
            "latest_hash": "9f0a1b2",
        },
    }
    # The deeplink is only rendered when an address is configured, which it is
    # not in a bare self-check run, so it is set for the length of this block.
    global KOMODO_HOST
    original_host, KOMODO_HOST = KOMODO_HOST, "https://komodo.example.com"
    repo_body = repo_failure_body(repo).split("\n")
    assert repo_body[0] == "**qbittorrent-scripts** - last pull failed", repo_body
    assert repo_body[1] == "", repo_body
    assert repo_body[2] == "📝 Source: smoochy/homelab (branch main)", repo_body
    assert repo_body[3] == "🔖 Cloned: 85f7052 - latest: 9f0a1b2", repo_body
    assert repo_body[-1].endswith("/repos/abc)"), repo_body
    assert "@" not in "\n".join(repo_body), repo_body
    # The reminder inserts its one line and changes nothing else, as above.
    repo_repeat = repo_failure_body(repo, 21720).split("\n")
    assert repo_repeat[1] == "⏱️ Failing for: 6h 2m", repo_repeat
    assert repo_repeat[2:] == repo_body[1:], repo_repeat
    # A repo Komodo knows nothing about still renders rather than raising.
    assert repo_failure_body({"name": "x", "info": {}}).split("\n")[3] == (
        "🔖 Cloned: none - latest: unknown"
    )
    KOMODO_HOST = original_host

    assert short_digest("ghcr.io/x/y:v1@sha256:0123456789abcdef") == "ghcr.io/x/y:v1 (01234567)"
    assert short_digest("ghcr.io/x/y:v1") == "ghcr.io/x/y:v1"
    assert short_digest("ghcr.io/x/y:v1", "sha256:0123456789abcdef") == "ghcr.io/x/y:v1 (01234567)"
    # A bare image id names no repository, and half a line beats none.
    assert short_digest("sha256:0123456789abcdef") == "01234567"
    assert short_digest(None, "sha256:0123456789abcdef") == "01234567"
    assert short_digest(None) == "unknown image"
    assert human_duration(45) == "45s" and human_duration(600) == "10m"
    assert human_duration(7800) == "2h 10m"

    # The labelled block is the one part of the message shape that can be
    # reflowed away by accident; the titles are literals, not logic.
    failures = [
        {"name": "qbittorrent", "reason": "unhealthy", "image": "lscr.io/q:5@sha256:0123456789abcdef"},
        {"name": "sonarr", "reason": "exited (exit 1)", "image": None},
    ]
    body = failure_body("qbittorrent", None, failures).split("\n")
    assert body[0] == "**qbittorrent** - 2 container(s) failing", body[0]
    assert body[1] == "" and body[5] == "", body
    assert body[2] == "**qbittorrent**", body
    assert body[3] == "📝 Reason: unhealthy", body
    assert body[4] == "📦 Image: lscr.io/q:5 (01234567)", body
    # Nothing that reaches Apprise may carry a bare `@`: its Discord plugin
    # reads one as a mention token and prefixes the message with a bogus ping.
    assert "@" not in "\n".join(body), body
    assert body[6] == "**sonarr**" and body[8] == "📦 Image: unknown image", body
    assert len(body) == 9, body

    # The reminder is the same block with one line inserted, and that line is
    # the whole reason the reminder stopped being a bare count.
    repeat = failure_body("qbittorrent", None, failures, 21720).split("\n")
    assert repeat[0] == body[0], repeat[0]
    assert repeat[1] == "⏱️ Failing for: 6h 2m", repeat[1]
    assert repeat[2:] == body[1:], repeat

    # The heartbeat marker is what the container's own healthcheck reads, so a
    # touch that silently fails would show up as an unhealthy container and
    # nowhere else. Written to a temporary path here rather than to /run, which
    # only exists inside the container.
    global HEARTBEAT_FILE
    original, HEARTBEAT_FILE = HEARTBEAT_FILE, os.path.join(
        tempfile.gettempdir(), "stack-health-self-check.heartbeat"
    )
    try:
        heartbeat()
        assert os.path.exists(HEARTBEAT_FILE), HEARTBEAT_FILE
        before = os.stat(HEARTBEAT_FILE).st_mtime
        os.utime(HEARTBEAT_FILE, (before - 300, before - 300))
        heartbeat()
        assert os.stat(HEARTBEAT_FILE).st_mtime > before - 300
        os.remove(HEARTBEAT_FILE)
        # An unwritable path must be logged and swallowed, never raised: the
        # poller keeps watching stacks even when its own marker cannot be written.
        HEARTBEAT_FILE = "/does/not/exist/stack-health.heartbeat"
        heartbeat()
    finally:
        HEARTBEAT_FILE = original

    print("self-check ok")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        main()
