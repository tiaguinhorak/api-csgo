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

if [[ -z "${AUTH_KEY}" || -z "${RCON_PW}" ]]; then
  echo "WARN: skip register (need API_KEY or CSGO_SKINS_SYNC_KEY + CSGO_RCON_PASSWORD)"
  exit 0
fi

LIST_JSON="$(curl -sf "http://127.0.0.1:${API_PORT}/api/servers" \
  -H "x-api-key: ${AUTH_KEY}" 2>/dev/null || true)"

if echo "${LIST_JSON}" | grep -q "\"host\":\"${HOST}\"" && \
   echo "${LIST_JSON}" | grep -q "\"port\":${PORT_GAME}"; then
  echo "Server already in api-csgo (${HOST}:${PORT_GAME})"
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
  tickrate: 128,
};
console.log(JSON.stringify(b));
" "${NAME}" "${HOST}" "${PORT_GAME}" "${RCON_PORT}" "${RCON_PW}" "${CSGO_DIR}" "${POOL}")"

RESP="$(curl -sf -X POST "http://127.0.0.1:${API_PORT}/api/servers" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${AUTH_KEY}" \
  -d "${BODY}" 2>/dev/null || echo '{}')"

if echo "${RESP}" | grep -q '"id"'; then
  echo "Registered: ${NAME} pool=${POOL} ${HOST}:${PORT_GAME}"
else
  echo "WARN: register failed — ${RESP}"
fi
