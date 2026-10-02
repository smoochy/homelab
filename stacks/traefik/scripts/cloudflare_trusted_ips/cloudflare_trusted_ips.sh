#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/cloudflare_trusted_ips.py"
ENV_FILE="${CLOUDFLARE_TRUSTED_IPS_ENV_FILE:-${SCRIPT_DIR}/.env}"

if command -v uv >/dev/null 2>&1; then
  exec uv run python "$PYTHON_SCRIPT" --env-file "$ENV_FILE" "$@"
fi

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$PYTHON_SCRIPT" --env-file "$ENV_FILE" "$@"
fi

printf 'missing required command: uv or python3\n' >&2
exit 1
