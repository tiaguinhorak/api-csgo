#!/usr/bin/env bash
set -euo pipefail

# Diagnóstico rápido: Steam auth + weapons DB + player-sync
#
# Uso na VPS:
#   cd ~/api-csgo && ./scripts/diagnose-steam-and-skins.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
DATA="${CLUTCH_SKINS_OUT:-${CSGO_ROOT}/addons/sourcemod/data/clutch_skins.txt}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:3000}"

echo "=== Steam + Skins diagnose ==="
echo ""

echo "--- 1) clutch_skins.txt (legacy, v3 ignores) ---"
if [[ -f "${DATA}" ]]; then
  echo "OK  ${DATA} ($(wc -c < "${DATA}") bytes)"
  head -12 "${DATA}"
else
  echo "MISSING ${DATA} (ok for v3)"
fi

echo ""
echo "--- 2) weapons SQLite (!ws / storage-local) ---"
SQLITE_DIR="${CSGO_ROOT}/addons/sourcemod/data/sqlite"
if [[ -d "${SQLITE_DIR}" ]]; then
  echo "Files in ${SQLITE_DIR}:"
  ls -la "${SQLITE_DIR}"/*.sq3 2>/dev/null || echo "  (no .sq3 files)"
else
  echo "MISSING dir ${SQLITE_DIR}"
fi

DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
echo ""
echo "WEAPONS_DB_PATH=${DB_PATH}"
if [[ -f "${DB_PATH}" ]]; then
  if [[ -r "${DB_PATH}" && -w "${DB_PATH}" ]]; then
    echo "OK  readable + writable"
    if command -v sqlite3 >/dev/null 2>&1; then
      TABLES="$(sqlite3 "${DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%weapons%';" 2>/dev/null || true)"
      if [[ -n "${TABLES}" ]]; then
        echo "OK  weapons table(s): ${TABLES}"
        echo "Sample loadout (knife_butterfly / bayonet / knife):"
        sqlite3 "${DB_PATH}" \
          "SELECT steamid, knife, knife_butterfly, bayonet FROM weapons WHERE knife_butterfly > 0 OR bayonet > 0 LIMIT 5;" \
          2>/dev/null || true
      else
        echo "WARN no 'weapons' table — use !ws once in-game or check databases.cfg"
      fi
    fi
  else
    echo "WARN exists but not rw — fix:"
    echo "  chmod 664 \"${DB_PATH}\" && chmod 775 \"$(dirname "${DB_PATH}")\""
  fi
else
  echo "MISSING — try:"
  echo "  find /home/csgo -name '*.sq3' 2>/dev/null"
  echo "  Typical: .../addons/sourcemod/data/sqlite/sourcemod-local.sq3"
fi

echo ""
echo "--- 3) api-csgo player-sync ---"
if [[ -z "${SYNC_KEY}" ]]; then
  echo "WARN  CSGO_SKINS_SYNC_KEY not set — source ~/api-csgo/.env first"
else
  HTTP="$(curl -sS -o /tmp/clutch-sync-test.out -w "%{http_code}" \
    -X POST "${API_URL}/api/csgo/skins/player-sync" \
    -H "x-skins-sync-key: ${SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"steamId":"STEAM_0:0:0","weapons":[]}' || echo "000")"
  echo "POST ${API_URL}/api/csgo/skins/player-sync → HTTP ${HTTP}"
  if [[ -f /tmp/clutch-sync-test.out ]]; then
    head -c 400 /tmp/clutch-sync-test.out; echo
  fi
  if [[ "${HTTP}" == "401" ]]; then
    echo "  → Key mismatch between site .env and api-csgo .env"
  fi
  if [[ "${HTTP}" == "500" ]]; then
    echo "  → Check WEAPONS_DB_PATH and chmod on .sq3 file"
  fi
  if [[ "${HTTP}" == "200" ]]; then
    echo "  → DB sync OK (rconReload may be false if server is hibernating — respawn still works)"
  fi
  if [[ "${HTTP}" == "000" ]]; then
    echo "  → api-csgo not running on ${API_URL} (pm2 restart --update-env?)"
  fi
fi

echo ""
echo "--- 4) RCON / screen ---"
RCON_HOST="${CSGO_SERVER_HOST:-127.0.0.1}"
RCON_PORT="${CSGO_RCON_PORT:-27015}"
if command -v nc >/dev/null 2>&1; then
  if nc -z -w2 "${RCON_HOST}" "${RCON_PORT}" 2>/dev/null; then
    echo "OK  TCP ${RCON_HOST}:${RCON_PORT} (RCON reachable)"
  else
    echo "WARN TCP ${RCON_HOST}:${RCON_PORT} refused — server hibernating/offline?"
    echo "  Set CLUTCH_CS_SCREEN=csgo-clutch-#1 in .env for screen fallback"
    screen -ls 2>/dev/null | grep -i csgo || true
  fi
else
  echo "SKIP nc not installed — install netcat-openbsd for RCON port check"
fi

echo ""
echo "--- 5) Steam / spawn ---"
echo "  BAD log: Could not establish connection to Steam servers → fix GSLT"
echo "  BAD log: PutClientInServer: no info_player_start → changelevel de_mirage"
echo ""
echo "--- 6) In-game ---"
echo "  sm plugins info z_clutch_skins_bridge  (must be 3.0.0)"
echo "  sm_clutch_applyskins && kill"
