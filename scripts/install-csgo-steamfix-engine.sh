#!/usr/bin/env bash
# Permite clientes CS:GO Global archivado (app 4465480) conectar ao srcds app 730.
# Fix: "Client connected with ticket for the wrong game" / STEAM validation rejected
# https://github.com/eonexdev/csgo-sv-fix-engine
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

CSGO_ROOT="${CSGO_ROOT:-${CSGO_SERVER_DIR:-/home/csgo/server}/csgo}"
EXT_DIR="${CSGO_ROOT}/addons/sourcemod/extensions"
BASE="https://raw.githubusercontent.com/eonexdev/csgo-sv-fix-engine/main"

if [[ ! -d "${EXT_DIR}" ]]; then
  echo "ERROR: ${EXT_DIR} not found — install SourceMod first" >&2
  exit 1
fi

echo ">>> csgo_steamfix extension (archived CS:GO clients)"
curl -fsSL "${BASE}/csgo_steamfix.ext.so" -o "${EXT_DIR}/csgo_steamfix.ext.so"
curl -fsSL "${BASE}/csgo_steamfix.autoload" -o "${EXT_DIR}/csgo_steamfix.autoload"
chmod +x "${EXT_DIR}/csgo_steamfix.ext.so" 2>/dev/null || true

if command -v file >/dev/null 2>&1; then
  echo "Arch: $(file -b "${EXT_DIR}/csgo_steamfix.ext.so")"
fi

echo "OK: ${EXT_DIR}/csgo_steamfix.ext.so"
echo "Restart srcds (extensions load at boot). Expect in console: [steamfix] engine patched!"
echo "Pair with: bash scripts/install-nolobby-reservation.sh"
