#!/usr/bin/env bash
set -euo pipefail

# Testa escrita na tabela gloves (player-sync) e mostra o resultado no SQLite.
#
# Uso:
#   cd ~/api-csgo && ./scripts/test-gloves-sync.sh STEAM_1:0:12345
#   ./scripts/test-gloves-sync.sh STEAM_1:0:12345 --clear

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

STEAM_ID="${1:-}"
MODE="${2:-apply}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:3000}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
PREFIX="${WEAPONS_TABLE_PREFIX:-}"
TABLE="${PREFIX}gloves"

if [[ -z "${STEAM_ID}" ]]; then
  echo "Usage: $0 STEAM_x:y:steamid [--clear]" >&2
  exit 1
fi

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

if [[ "${MODE}" == "--clear" ]]; then
  BODY="$(cat <<EOF
{"steamId":"${STEAM_ID}","weapons":[],"clearWeaponIds":["leather_handwraps"]}
EOF
)"
else
  BODY="$(cat <<EOF
{"steamId":"${STEAM_ID}","weapons":[{"weaponId":"leather_handwraps","paintkit":10010,"wear":0.15,"defIndex":5032}]}
EOF
)"
fi

echo "POST ${API_URL}/api/csgo/skins/player-sync"
HTTP="$(curl -sS -o /tmp/clutch-gloves-test.json -w "%{http_code}" \
  -X POST "${API_URL}/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d "${BODY}")"
echo "HTTP ${HTTP}"
cat /tmp/clutch-gloves-test.json
echo ""

if command -v sqlite3 >/dev/null 2>&1 && [[ -f "${DB_PATH}" ]]; then
  echo "--- ${TABLE} ---"
  sqlite3 "${DB_PATH}" "SELECT steamid,t_group,t_glove,ct_group,ct_glove FROM ${TABLE} WHERE steamid LIKE '%${STEAM_ID#STEAM_1:}%' OR steamid LIKE '%${STEAM_ID#STEAM_0:}%';"
fi
