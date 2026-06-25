#!/usr/bin/env bash
# Verifica stack local: site :3000, api-csgo :3001, SQLite, opcional RCON.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3001}"
API_URL="http://127.0.0.1:${PORT}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
SITE_URL="${CLUTCH_SITE_URL:-http://127.0.0.1:3000}"
RCON_HOST="${CSGO_SERVER_HOST:-127.0.0.1}"
RCON_PORT="${CSGO_RCON_PORT:-27015}"

echo "=== Clutch local stack verify ==="
echo "api-csgo: ${API_URL}"
echo "site:     ${SITE_URL}"
echo "SQLite:   ${DB_PATH}"
echo ""

FAIL=0

check() {
  local label="$1"
  if eval "$2"; then
    echo "OK  ${label}"
  else
    echo "FAIL ${label}"
    FAIL=$((FAIL + 1))
  fi
}

check "api-csgo health" "curl -sf \"${API_URL}/health\" | grep -q ok"
check "site reachable" "curl -sf -o /dev/null \"${SITE_URL}/\""

if [[ -f "${DB_PATH}" ]]; then
  echo "OK  SQLite file exists"
  if command -v sqlite3 >/dev/null 2>&1; then
    echo "    clutch_team_loadout rows: $(sqlite3 "${DB_PATH}" 'SELECT COUNT(*) FROM clutch_team_loadout;' 2>/dev/null || echo '?')"
    echo "    gloves rows: $(sqlite3 "${DB_PATH}" 'SELECT COUNT(*) FROM gloves;' 2>/dev/null || echo '?')"
  fi
else
  echo "FAIL SQLite missing: ${DB_PATH}"
  FAIL=$((FAIL + 1))
fi

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  HTTP="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    "${SITE_URL}/api/csgo/skins/equipped-loadouts" 2>/dev/null || echo 000)"
  if [[ "${HTTP}" == "200" ]]; then
    echo "OK  site equipped-loadouts API (HTTP 200)"
  else
    echo "WARN site equipped-loadouts HTTP ${HTTP} (equip skins on site first?)"
  fi
else
  echo "WARN CSGO_SKINS_SYNC_KEY not set"
fi

if command -v nc >/dev/null 2>&1; then
  if nc -z "${RCON_HOST}" "${RCON_PORT}" 2>/dev/null; then
    echo "OK  CS:GO port ${RCON_PORT} open on ${RCON_HOST}"
  else
    echo "WARN CS:GO port ${RCON_PORT} not reachable (srcds not running?)"
  fi
fi

BRIDGE_CFG="${CSGO_SERVER_DIR:-/home/csgo/server}/csgo/cfg/sourcemod/clutch_skins_bridge.cfg"
if [[ -f "${BRIDGE_CFG}" ]]; then
  echo "OK  bridge cfg: ${BRIDGE_CFG}"
  grep -E 'clutch_skins_defer_live|clutch_skins_once_per_match|clutch_skins_debug' "${BRIDGE_CFG}" || true
else
  echo "WARN bridge cfg not found (install-clutch-skins-bridge.sh?)"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "Stack looks ready. Connect: connect ${CSGO_PUBLIC_HOST:-127.0.0.1}:${RCON_PORT}"
  exit 0
fi
echo "${FAIL} critical check(s) failed — see LOCAL-DEV.md"
exit 1
