#!/usr/bin/env python3
"""Refresh Cloudflare trusted IPs for Traefik and CrowdSec."""

from __future__ import annotations

import argparse
import importlib.util
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


BEGIN_MARKER = "# BEGIN CLOUDFLARE IPs (managed by script)"
END_MARKER = "# END CLOUDFLARE IPs (managed by script)"
TARGET_ENV_KEY = "CROWDSEC_FORWARDED_HEADERS_TRUSTED_IPS"
CURRENT_LOG_SECTION: str | None = None


@dataclass(frozen=True)
class Config:
    traefik_config_path: Path
    traefik_dynamic_config_path: Path
    traefik_backup_dir: Path
    runtime_env_path: Path
    temp_repo_base: Path
    repo_url: str
    repo_branch: str
    repo_env_enc_relpath: Path
    repo_env_example_relpath: Path
    commit_message: str
    git_author_name: str
    git_author_email: str
    periphery_container: str
    periphery_sops_age_key_file: str
    cloudflare_ipv4_url: str
    cloudflare_ipv6_url: str


def log(message: str) -> None:
    print(f"{datetime.now():%F %T} {message}")


def log_section(section: str | None) -> None:
    global CURRENT_LOG_SECTION

    if not section:
        return
    if CURRENT_LOG_SECTION is None:
        CURRENT_LOG_SECTION = section
        return
    if CURRENT_LOG_SECTION != section:
        print("")
        CURRENT_LOG_SECTION = section


def log_step(step: str, detail: str | None = None, *, section: str | None = None) -> None:
    log_section(section)
    prefix = "[STEP]"
    if detail:
        log(f"{prefix} {step}: {detail}")
    else:
        log(f"{prefix} {step}")


def log_ok(step: str, detail: str | None = None, *, section: str | None = None) -> None:
    log_section(section)
    prefix = "[OK]"
    if detail:
        log(f"{prefix} {step}: {detail}")
    else:
        log(f"{prefix} {step}")


def log_skip(step: str, detail: str | None = None, *, section: str | None = None) -> None:
    log_section(section)
    prefix = "[SKIP]"
    if detail:
        log(f"{prefix} {step}: {detail}")
    else:
        log(f"{prefix} {step}")


def log_error(step: str, detail: str | None = None, *, section: str | None = None) -> None:
    log_section(section)
    prefix = "[ERROR]"
    if detail:
        log(f"{prefix} {step}: {detail}")
    else:
        log(f"{prefix} {step}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh Cloudflare trusted IPs in Traefik and CrowdSec."
    )
    parser.add_argument(
        "--env-file",
        help="Optional dotenv-style config file used to populate runtime settings.",
    )
    return parser.parse_args()


def strip_inline_comment(value: str) -> str:
    in_single = False
    in_double = False
    result: list[str] = []

    for index, character in enumerate(value):
        previous = value[index - 1] if index > 0 else ""
        if character == "'" and not in_double and previous != "\\":
            in_single = not in_single
        elif character == '"' and not in_single and previous != "\\":
            in_double = not in_double
        elif character == "#" and not in_single and not in_double:
            break
        result.append(character)

    return "".join(result).strip()


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = strip_inline_comment(value)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        os.environ.setdefault(key, value)


def env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


def env_str(name: str, default: str) -> str:
    return os.environ.get(name, default)


def build_config(args: argparse.Namespace) -> Config:
    if args.env_file:
        load_env_file(Path(args.env_file).expanduser())

    return Config(
        traefik_config_path=env_path(
            "TRAEFIK_CONFIG_PATH", "/mnt/user/appdata/traefik/traefik.yml"
        ),
        traefik_dynamic_config_path=env_path(
            "TRAEFIK_DYNAMIC_CONFIG_PATH", "/mnt/user/appdata/traefik/dynamic.yml"
        ),
        traefik_backup_dir=env_path(
            "TRAEFIK_BACKUP_DIR", "/mnt/user/appdata/traefik/backups"
        ),
        runtime_env_path=env_path(
            "TRAEFIK_RUNTIME_ENV_PATH",
            "/mnt/user/appdata/komodo/repos/homelab-private/stacks/traefik/.env",
        ),
        temp_repo_base=env_path(
            "TEMP_REPO_BASE", "/mnt/user/appdata/komodo/root/tmp"
        ),
        repo_url=env_str(
            "HOMELAB_PRIVATE_REPO_URL", "git@github.com:smoochy/homelab-private.git"
        ),
        repo_branch=env_str("HOMELAB_PRIVATE_REPO_BRANCH", "main"),
        repo_env_enc_relpath=Path(
            env_str("HOMELAB_PRIVATE_ENV_ENC_PATH", "stacks/traefik/.env.enc")
        ),
        repo_env_example_relpath=Path(
            env_str("HOMELAB_PRIVATE_ENV_EXAMPLE_PATH", "stacks/traefik/.env.example")
        ),
        commit_message=env_str(
            "HOMELAB_PRIVATE_COMMIT_MESSAGE",
            "[Traefik] Refresh Cloudflare trusted IPs",
        ),
        git_author_name=env_str("GIT_AUTHOR_NAME", "Cloudflare Trusted IP Sync"),
        git_author_email=env_str(
            "GIT_AUTHOR_EMAIL", "cloudflare-trusted-ips@local.invalid"
        ),
        periphery_container=env_str("PERIPHERY_CONTAINER", "komodo-periphery"),
        periphery_sops_age_key_file=env_str(
            "PERIPHERY_SOPS_AGE_KEY_FILE", "/root/.config/sops/age/keys.txt"
        ),
        cloudflare_ipv4_url=env_str(
            "CLOUDFLARE_IPV4_URL", "https://www.cloudflare.com/ips-v4"
        ),
        cloudflare_ipv6_url=env_str(
            "CLOUDFLARE_IPV6_URL", "https://www.cloudflare.com/ips-v6"
        ),
    )


def require_path_exists(path: Path, description: str) -> None:
    log_step("validate path", f"{description} -> {path}", section="validation")
    if not path.exists():
        raise RuntimeError(f"{description} not found: {path}")
    log_ok("validate path", f"{description} found", section="validation")


def normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def fetch_cloudflare_ips(url: str) -> list[str]:
    log_step("fetch Cloudflare IPs", url, section="cloudflare fetch")
    request = Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/123.0.0.0 Safari/537.36"
            ),
            "Accept": "text/plain,text/*;q=0.9,*/*;q=0.8",
            "Cache-Control": "no-cache",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            content = response.read().decode("utf-8")
    except HTTPError as exc:
        raise RuntimeError(f"failed to fetch {url}: HTTP {exc.code}") from exc
    except URLError as exc:
        raise RuntimeError(f"failed to fetch {url}: {exc.reason}") from exc

    ips = [line.strip() for line in normalize_newlines(content).splitlines() if line.strip()]
    if not ips:
        raise RuntimeError(f"Cloudflare response was empty for {url}")
    log_ok("fetch Cloudflare IPs", f"{url} returned {len(ips)} entries", section="cloudflare fetch")
    return ips


def build_managed_block(ipv4_networks: Iterable[str], ipv6_networks: Iterable[str]) -> str:
    lines = [f"        {BEGIN_MARKER}", "        # Cloudflare IPv4"]
    lines.extend(f'        - "{network}"' for network in ipv4_networks)
    lines.append("        # Cloudflare IPv6")
    lines.extend(f'        - "{network}"' for network in ipv6_networks)
    lines.append(f"        {END_MARKER}")
    return "\n".join(lines) + "\n"


def replace_managed_block(content: str, new_block: str) -> str:
    lines = normalize_newlines(content).splitlines(keepends=True)
    start_index = -1
    end_index = -1

    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == BEGIN_MARKER:
            start_index = index
        elif stripped == END_MARKER:
            end_index = index
            if start_index != -1:
                break

    if start_index == -1 or end_index == -1 or end_index < start_index:
        raise RuntimeError("managed Cloudflare block was not found in traefik.yml")

    return "".join(lines[:start_index]) + new_block + "".join(lines[end_index + 1 :])


def update_env_value(content: str, key: str, value: str) -> str:
    normalized = normalize_newlines(content)
    lines = normalized.splitlines()
    replacement = f"{key}={value}"

    for index, line in enumerate(lines):
        if "=" in line and line.split("=", 1)[0].strip() == key:
            lines[index] = replacement
            break
    else:
        lines.append(replacement)

    return "\n".join(lines) + "\n"


def load_env_example_renderer(temp_repo_dir: Path):
    module_path = temp_repo_dir / "scripts/public_export/env_example_renderer.py"
    if not module_path.exists():
        raise RuntimeError(f"env example renderer not found in temporary repo: {module_path}")

    module_name = "temp_env_example_renderer"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load env example renderer from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def render_repo_env_example(config: Config, temp_repo_dir: Path) -> tuple[Path, str]:
    target_env_example_path = temp_repo_dir / config.repo_env_example_relpath
    log_step(
        "render env example",
        f"{config.runtime_env_path} -> {target_env_example_path}",
        section="env example",
    )
    renderer = load_env_example_renderer(temp_repo_dir)
    rendered = renderer.render_env_example_from_path("traefik", config.runtime_env_path)
    log_ok("render env example", str(target_env_example_path), section="env example")
    return target_env_example_path, rendered


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    log_step("write file", str(path), section="file updates")
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", newline="\n", delete=False, dir=path.parent
    ) as temporary:
        temporary.write(content)
        temp_path = Path(temporary.name)
    temp_path.replace(path)
    log_ok("write file", str(path), section="file updates")


def run_command(
    command: list[str],
    *,
    cwd: Path | None = None,
    description: str | None = None,
    section: str | None = None,
) -> subprocess.CompletedProcess[str]:
    if description:
        log_section(section)
        if cwd:
            log_step(description, f"cwd={cwd}")
        else:
            log_step(description)
    completed = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        check=True,
        text=True,
        capture_output=True,
    )
    if description:
        log_ok(description, section=section)
    return completed


def create_runtime_backups(config: Config) -> None:
    log_step("create backups", f"target directory {config.traefik_backup_dir}", section="backups")
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    config.traefik_backup_dir.mkdir(parents=True, exist_ok=True)

    backup_targets = {
        config.traefik_config_path: config.traefik_backup_dir / f"traefik-{timestamp}.yml",
        config.traefik_dynamic_config_path: config.traefik_backup_dir / f"dynamic-{timestamp}.yml",
    }

    for source_path, backup_path in backup_targets.items():
        log_step("backup file", f"{source_path} -> {backup_path}", section="backups")
        shutil.copy2(source_path, backup_path)
        log_ok("backup file", str(backup_path), section="backups")
    log_ok("create backups", f"created {len(backup_targets)} backup files with timestamp {timestamp}", section="backups")


def ensure_temp_repo(config: Config) -> Path:
    log_step("prepare temporary repo", f"base directory {config.temp_repo_base}", section="git sync")
    config.temp_repo_base.mkdir(parents=True, exist_ok=True)
    temp_repo_dir = Path(
        tempfile.mkdtemp(prefix="cloudflare-trusted-ips-", dir=config.temp_repo_base)
    )
    try:
        run_command(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                config.repo_branch,
                config.repo_url,
                str(temp_repo_dir),
            ],
            description=f"clone temporary repo into {temp_repo_dir}",
            section="git sync",
        )
        log_ok("prepare temporary repo", str(temp_repo_dir), section="git sync")
        return temp_repo_dir
    except Exception:
        shutil.rmtree(temp_repo_dir, ignore_errors=True)
        raise


def map_host_path_to_periphery(path: Path) -> str:
    normalized = path.as_posix()
    host_repos_prefix = "/mnt/user/appdata/komodo/repos"
    host_root_prefix = "/mnt/user/appdata/komodo/root"

    if normalized == host_repos_prefix:
        return "/etc/komodo/repos"
    if normalized.startswith(host_repos_prefix + "/"):
        return "/etc/komodo/repos" + normalized[len(host_repos_prefix) :]
    if normalized == host_root_prefix:
        return "/root"
    if normalized.startswith(host_root_prefix + "/"):
        return "/root" + normalized[len(host_root_prefix) :]

    raise RuntimeError(
        f"path is not mounted inside {env_str('PERIPHERY_CONTAINER', 'komodo-periphery')}: {path}"
    )


def encrypt_runtime_env(
    config: Config, runtime_env_path: Path, target_env_enc_path: Path
) -> None:
    log_step(
        "encrypt runtime env",
        f"{runtime_env_path} -> {target_env_enc_path} via {config.periphery_container}",
        section="git sync",
    )
    runtime_env_container_path = map_host_path_to_periphery(runtime_env_path)
    target_env_enc_container_path = map_host_path_to_periphery(target_env_enc_path)
    target_parent_container = map_host_path_to_periphery(target_env_enc_path.parent)

    shell_script = f"""
set -euo pipefail
mkdir -p {shlex.quote(target_parent_container)}
age_key="$(age-keygen -y {shlex.quote(config.periphery_sops_age_key_file)})"
sops --encrypt --age "$age_key" --input-type dotenv --output-type dotenv --output {shlex.quote(target_env_enc_container_path)} {shlex.quote(runtime_env_container_path)}
"""

    run_command(
        [
            "docker",
            "exec",
            "-e",
            f"SOPS_AGE_KEY_FILE={config.periphery_sops_age_key_file}",
            config.periphery_container,
            "sh",
            "-lc",
            shell_script,
        ],
        description="run sops encryption inside komodo-periphery",
        section="git sync",
    )
    log_ok("encrypt runtime env", str(target_env_enc_path), section="git sync")


def repo_files_changed(repo_dir: Path, relative_paths: list[Path]) -> bool:
    joined_paths = ", ".join(str(path) for path in relative_paths)
    log_step("check repo diff", f"{repo_dir} -> {joined_paths}", section="git sync")
    result = subprocess.run(
        ["git", "-C", str(repo_dir), "diff", "--quiet", "--", *[str(path) for path in relative_paths]],
        text=True,
        capture_output=True,
    )
    if result.returncode not in {0, 1}:
        raise RuntimeError(result.stderr.strip() or "git diff failed")
    changed = result.returncode == 1
    if changed:
        log_ok("check repo diff", "changes detected", section="git sync")
    else:
        log_ok("check repo diff", "no changes detected", section="git sync")
    return changed


def commit_and_push(config: Config, repo_dir: Path, relative_paths: list[Path]) -> None:
    joined_paths = ", ".join(str(path) for path in relative_paths)
    log_step("commit and push", f"{joined_paths} -> {config.repo_branch}", section="git sync")
    run_command(
        ["git", "-C", str(repo_dir), "add", "--", *[str(path) for path in relative_paths]],
        description="stage updated repo env artifacts",
        section="git sync",
    )
    run_command(
        [
            "git",
            "-C",
            str(repo_dir),
            "-c",
            f"user.name={config.git_author_name}",
            "-c",
            f"user.email={config.git_author_email}",
            "commit",
            "-m",
            config.commit_message,
        ],
        description="create git commit",
        section="git sync",
    )
    run_command(
        ["git", "-C", str(repo_dir), "push", "origin", config.repo_branch],
        description="push commit to origin",
        section="git sync",
    )
    log_ok("commit and push", "git update completed", section="git sync")


def main() -> int:
    global CURRENT_LOG_SECTION
    CURRENT_LOG_SECTION = None
    args = parse_args()
    log_step("start", "Cloudflare Trusted IP sync", section="startup")
    config = build_config(args)
    log_ok(
        "load configuration",
        (
            f"traefik={config.traefik_config_path}, "
            f"dynamic={config.traefik_dynamic_config_path}, "
            f"runtime_env={config.runtime_env_path}"
        ),
        section="startup",
    )

    require_path_exists(config.traefik_config_path, "Traefik config")
    require_path_exists(config.traefik_dynamic_config_path, "Traefik dynamic config")
    require_path_exists(config.runtime_env_path, "Traefik runtime .env")
    create_runtime_backups(config)

    ipv4_networks = fetch_cloudflare_ips(config.cloudflare_ipv4_url)
    ipv6_networks = fetch_cloudflare_ips(config.cloudflare_ipv6_url)
    log_ok(
        "build IP payload",
        f"prepared {len(ipv4_networks)} IPv4 and {len(ipv6_networks)} IPv6 ranges",
        section="cloudflare fetch",
    )
    csv_value = ",".join([*ipv4_networks, *ipv6_networks])
    managed_block = build_managed_block(ipv4_networks, ipv6_networks)

    log_step("read runtime files", "loading traefik.yml and runtime .env", section="comparison")
    traefik_content = config.traefik_config_path.read_text(encoding="utf-8")
    updated_traefik_content = replace_managed_block(traefik_content, managed_block)
    traefik_changed = normalize_newlines(traefik_content) != normalize_newlines(
        updated_traefik_content
    )

    runtime_env_content = config.runtime_env_path.read_text(encoding="utf-8")
    updated_runtime_env = update_env_value(runtime_env_content, TARGET_ENV_KEY, csv_value)
    runtime_env_changed = normalize_newlines(runtime_env_content) != normalize_newlines(
        updated_runtime_env
    )
    log_ok(
        "compare desired state",
        f"traefik_changed={traefik_changed}, runtime_env_changed={runtime_env_changed}",
        section="comparison",
    )

    if not traefik_changed and not runtime_env_changed:
        log_ok("finish", "Cloudflare trusted IPs are already up to date", section="finish")
        return 0

    if traefik_changed:
        write_atomic(config.traefik_config_path, updated_traefik_content)
    else:
        log_skip("file update", f"no change needed for {config.traefik_config_path}", section="file updates")

    if runtime_env_changed:
        write_atomic(config.runtime_env_path, updated_runtime_env)
    else:
        log_skip("file update", f"no change needed for {config.runtime_env_path}", section="file updates")
        log_skip("git sync", f"no push required because {config.runtime_env_path} did not change", section="git sync")
        log_ok("finish", "host files processed without GitHub sync", section="finish")
        return 0

    temp_repo_dir: Path | None = None
    try:
        temp_repo_dir = ensure_temp_repo(config)
        target_env_enc_path = temp_repo_dir / config.repo_env_enc_relpath
        require_path_exists(target_env_enc_path, "Temporary repo .env.enc target")
        target_env_example_path, rendered_env_example = render_repo_env_example(config, temp_repo_dir)

        encrypt_runtime_env(config, config.runtime_env_path, target_env_enc_path)
        current_env_example = (
            target_env_example_path.read_text(encoding="utf-8")
            if target_env_example_path.exists()
            else ""
        )
        env_example_changed = normalize_newlines(current_env_example) != normalize_newlines(
            rendered_env_example
        )
        if env_example_changed:
            write_atomic(target_env_example_path, rendered_env_example)
        else:
            log_skip(
                "env example update",
                f"no change needed for {target_env_example_path}",
                section="env example",
            )

        repo_artifacts = [config.repo_env_enc_relpath, config.repo_env_example_relpath]
        if not repo_files_changed(temp_repo_dir, repo_artifacts):
            log_skip(
                "git sync",
                "temporary repo .env.enc and .env.example match main; skipping commit and push",
                section="git sync",
            )
            log_ok(
                "finish",
                "runtime .env changed locally, but repo-tracked env artifacts stayed unchanged",
                section="finish",
            )
            return 0

        commit_and_push(config, temp_repo_dir, repo_artifacts)
        log_ok(
            "finish",
            "pushed refreshed stacks/traefik/.env.enc and stacks/traefik/.env.example to origin/main",
            section="finish",
        )
        return 0
    finally:
        if temp_repo_dir and temp_repo_dir.exists():
            log_step("cleanup", f"remove temporary repo {temp_repo_dir}", section="cleanup")
            shutil.rmtree(temp_repo_dir, ignore_errors=True)
            log_ok("cleanup", f"removed temporary repo {temp_repo_dir}", section="cleanup")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else ""
        stdout = exc.stdout.strip() if exc.stdout else ""
        message = stderr or stdout or str(exc)
        log_error("command failed", message, section="error")
        raise SystemExit(1)
    except Exception as exc:  # pragma: no cover - top-level operational logging
        log_error("unhandled exception", str(exc), section="error")
        raise SystemExit(1)
