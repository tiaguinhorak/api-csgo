#!/usr/bin/env bash
# Writes sample TR/CT rows to clutch_team_loadout (proves api + SQLite + plugin path).
# Usage: bash scripts/test-team-loadout-write.sh [STEAM_1:0:Y]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

STEAM="${1:-STEAM_1:0:203852188}"
PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

echo "=== Test team loadout write ==="
echo "steamId: ${STEAM}"
echo "API: ${API_URL}"

BODY="$(cat <<EOF
{
  "steamId": "${STEAM}",
  "weapons": [
    {"weaponId":"weapon_glock","paintkit":1119,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"nametag":null,"team":"T"},
    {"weaponId":"weapon_hkp2000","paintkit":550,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"nametag":null,"team":"CT"},
    {"weaponId":"weapon_knife_widowmaker","paintkit":415,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"nametag":null,"team":"T"},
    {"weaponId":"weapon_knife_widowmaker","paintkit":415,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"nametag":null,"team":"CT"}
  ]
}
EOF
)"

RESULT="$(curl -sf -X POST "${API_URL}/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d "${BODY}" 2>/dev/null || true)"
echo "api response: ${RESULT:-<failed>}"

echo ""
echo "=== clutch_team_loadout ==="
sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS total FROM clutch_team_loadout;"
sqlite3 "${DB_PATH}" "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout WHERE steamid LIKE '%203852188%' OR steamid LIKE '%$(echo "${STEAM}" | grep -oE '[0-9]+$')%';"

echo ""
echo "If rows appear: API/SQLite OK — re-equip on site (gameSync.ok) or fix Hostinger CSGO_API_URL."
echo "In-game: sm plugins reload z_clutch_skins_bridge && respawn / swap team"
