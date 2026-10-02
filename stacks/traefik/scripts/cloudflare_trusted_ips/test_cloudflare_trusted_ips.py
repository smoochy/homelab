# Pins expand_env_defaults(), the ${VAR:-default} expander that lets the
# .env.example clone path (issue #1697) use the same house style as
# compose.yaml instead of hardcoding the Komodo repo name.
# Run it with `python stacks/traefik/scripts/cloudflare_trusted_ips/test_cloudflare_trusted_ips.py`.

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cloudflare_trusted_ips as cti  # noqa: E402

PATH_TEMPLATE = "/mnt/user/appdata/komodo/repos/homelab/stacks/traefik/.env"


def test_default_is_used_when_unset() -> None:
    os.environ.pop("KOMODO_REPO_NAME", None)
    assert cti.expand_env_defaults(PATH_TEMPLATE) == (
        "/mnt/user/appdata/komodo/repos/homelab/stacks/traefik/.env"
    )


def test_env_var_overrides_default() -> None:
    os.environ["KOMODO_REPO_NAME"] = "homelab"
    try:
        assert cti.expand_env_defaults(PATH_TEMPLATE) == (
            "/mnt/user/appdata/komodo/repos/homelab/stacks/traefik/.env"
        )
    finally:
        del os.environ["KOMODO_REPO_NAME"]


def test_load_env_file_expands_the_house_style_value(tmp_path_factory=None) -> None:
    import tempfile

    os.environ.pop("KOMODO_REPO_NAME", None)
    os.environ.pop("TRAEFIK_RUNTIME_ENV_PATH", None)
    with tempfile.TemporaryDirectory() as tmp:
        env_file = os.path.join(tmp, ".env")
        with open(env_file, "w", encoding="utf-8") as handle:
            handle.write(f'TRAEFIK_RUNTIME_ENV_PATH="{PATH_TEMPLATE}"\n')
        cti.load_env_file(cti.Path(env_file))
        try:
            assert os.environ["TRAEFIK_RUNTIME_ENV_PATH"] == (
                "/mnt/user/appdata/komodo/repos/homelab/stacks/traefik/.env"
            )
        finally:
            del os.environ["TRAEFIK_RUNTIME_ENV_PATH"]


if __name__ == "__main__":
    test_default_is_used_when_unset()
    test_env_var_overrides_default()
    test_load_env_file_expands_the_house_style_value()
    print("ok")
