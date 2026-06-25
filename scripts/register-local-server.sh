#!/usr/bin/env bash
# Register this VPS game server in local api-csgo (pool from SERVER_PROFILE).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f .env ]]; then
  echo "Skip register: no .env"
  exit 0
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/profile.sh"
clutch_profile_init "${REPO_ROOT}"

API_PORT="${PORT:-3001}"
AUTH_KEY="${API_KEY:-${CSGO_API_KEY:-${CSGO_SKINS_SYNC_KEY:-}}}"
HOST="${CSGO_PUBLIC_HOST:-${CSGO_SERVER_HOST:-127.0.0.1}}"
PORT_GAME="${CSGO_RCON_PORT:-27015}"
RCON_PORT="${CSGO_RCON_PORT:-27015}"
RCON_PW="${CSGO_RCON_PASSWORD:-}"
CSGO_DIR="${CSGO_SERVER_DIR:-/home/csgo/server}"
NAME="${SERVER_NAME:-${CLUTCH_SERVER_NAME}}"
POOL="${CSGO_SERVER_POOL:-${CLUTCH_SERVER_POOL}}"
SCREEN="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"

if [[ -z "${AUTH_KEY}" || -z "${RCON_PW}" ]]; then
  echo "WARN: skip register (need API_KEY or CSGO_SKINS_SYNC_KEY + CSGO_RCON_PASSWORD)"
  exit 0
fi

LIST_JSON="$(curl -sf "http://127.0.0.1:${API_PORT}/api/servers" \
  -H "x-api-key: ${AUTH_KEY}" 2>/dev/null || true)"

# Remove stale 127.0.0.1 / LAN entries when CSGO_PUBLIC_HOST is set (duplicate confuses site).
if [[ -n "${LIST_JSON}" && "${HOST}" != "127.0.0.1" && ! "${HOST}" =~ ^192\.168\. ]]; then
  STALE_IDS="$(echo "${LIST_JSON}" | node -e "
const port = Number(process.argv[1]);
const keep = process.argv[2];
let list = [];
try { list = JSON.parse(require('fs').readFileSync(0, 'utf8')); } catch { process.exit(0); }
if (!Array.isArray(list)) list = [list];
for (const s of list) {
  if (!s || s.port !== port || s.host === keep) continue;
  if (s.host === '127.0.0.1' || s.host.startsWith('192.168.') || s.host.startsWith('10.')) {
    console.log(s.id);
  }
}
" "${PORT_GAME}" "${HOST}" 2>/dev/null || true)"
  while IFS= read -r stale_id; do
    [[ -z "${stale_id}" ]] && continue
    if curl -sf -X DELETE "http://127.0.0.1:${API_PORT}/api/servers/${stale_id}" \
      -H "x-api-key: ${AUTH_KEY}" >/dev/null; then
      echo "Removed stale registry entry ${stale_id} (private host, port ${PORT_GAME})"
    fi
  done <<< "${STALE_IDS}"
fi

EXISTING_ID="$(echo "${LIST_JSON}" | node -e "
const host = process.argv[1];
const port = Number(process.argv[2]);
let list = [];
try { list = JSON.parse(require('fs').readFileSync(0, 'utf8')); } catch { process.exit(0); }
if (!Array.isArray(list)) list = [list];
for (const s of list) {
  if (s && s.host === host && s.port === port) {
    console.log(s.id);
    break;
  }
}
" "${HOST}" "${PORT_GAME}" 2>/dev/null || true)"

if [[ -n "${EXISTING_ID}" ]]; then
  PATCH_BODY="$(node -e "console.log(JSON.stringify({ screenSession: process.argv[1] }))" "${SCREEN}")"
  curl -sf -X PATCH "http://127.0.0.1:${API_PORT}/api/servers/${EXISTING_ID}" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${AUTH_KEY}" \
    -d "${PATCH_BODY}" >/dev/null 2>&1 || true
  echo "Server already in api-csgo (${HOST}:${PORT_GAME}) id=${EXISTING_ID} screen=${SCREEN}"
  exit 0
fi

BODY="$(node -e "
const b = {
  name: process.argv[1],
  host: process.argv[2],
  port: Number(process.argv[3]),
  rconPort: Number(process.argv[4]),
  rconPassword: process.argv[5],
  csgoDir: process.argv[6],
  pool: process.argv[7],
  screenSession: process.argv[8],
  tickrate: 128,
};
console.log(JSON.stringify(b));
" "${NAME}" "${HOST}" "${PORT_GAME}" "${RCON_PORT}" "${RCON_PW}" "${CSGO_DIR}" "${POOL}" "${SCREEN}")"

RESP="$(curl -sf -X POST "http://127.0.0.1:${API_PORT}/api/servers" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${AUTH_KEY}" \
  -d "${BODY}" 2>/dev/null || echo '{}')"

if echo "${RESP}" | grep -q '"id"'; then
  echo "Registered: ${NAME} pool=${POOL} ${HOST}:${PORT_GAME} screen=${SCREEN}"
else
  echo "WARN: register failed — ${RESP}"
fi
