#!/usr/bin/env bash
# Shared: load .env, resolve PORT, ensure pm2 (global or local node_modules).
set -euo pipefail

_PM2_LOCAL_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${_PM2_LOCAL_REPO}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

export PORT="${PORT:-3000}"
export API_PORT="${PORT}"
export CLUTCH_API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"

pm2_ensure_installed() {
  if command -v pm2 >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "${_PM2_LOCAL_REPO}/node_modules/.bin/pm2" ]]; then
    return 0
  fi
  echo "[pm2] pm2 not in PATH — installing locally (npm install pm2 --no-save)..."
  npm install pm2 --no-save --no-audit --no-fund
}

pm2_ensure_installed
export PATH="${_PM2_LOCAL_REPO}/node_modules/.bin:${PATH}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "ERROR: pm2 not available after install" >&2
  exit 1
fi
