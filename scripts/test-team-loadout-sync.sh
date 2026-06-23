#!/usr/bin/env bash
# Proves player-sync writes clutch_team_loadout (weapons need team T|CT).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

STEAM_ID="${1:-}"
PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
RESPONSE_FILE="/tmp/clutch-team-loadout-test.json"

if [[ -z "${STEAM_ID}" ]]; then
  echo "Usage: $0 STEAM_x:y:steamid" >&2
  exit 1
fi
if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

# Sample CT loadout — Poseidon-ish M4, deagle, M9, gloves (matches ichi test account pattern).
BODY="$(cat <<EOF
{
  "steamId": "${STEAM_ID}",
  "weapons": [
    {"weaponId":"weapon_m4a1","paintkit":449,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"team":"CT"},
    {"weaponId":"weapon_deagle","paintkit":711,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"team":"CT"},
    {"weaponId":"weapon_knife_m9_bayonet","paintkit":415,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"team":"CT"},
    {"weaponId":"leather_handwraps","paintkit":10010,"wear":0.15,"seed":0,"stattrak":false,"stattrakCount":0,"defIndex":5032,"team":"CT"}
  ]
}
EOF
)"

echo ">>> POST ${API_URL}/api/csgo/skins/player-sync"
HTTP="$(curl -sS -o "${RESPONSE_FILE}" -w "%{http_code}" \
  -X POST "${API_URL}/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d "${BODY}")"
echo "HTTP ${HTTP}"
cat "${RESPONSE_FILE}"
echo ""

if [[ "${HTTP}" != "200" ]]; then
  echo "ERROR: player-sync failed" >&2
  exit 1
fi

if grep -q '"skippedCs2":[1-9]' "${RESPONSE_FILE}"; then
  echo ""
  echo "WARN: skippedCs2 > 0 — api-csgo may still filter weapons via !ws allowlist." >&2
  echo "  Run: cd ~/api-csgo && git pull && ./deploy.sh" >&2
fi

if ! command -v sqlite3 >/dev/null 2>&1 || [[ ! -f "${DB_PATH}" ]]; then
  echo "sqlite3 or DB missing — skip row check"
  exit 0
fi

STEAM_SUFFIX="${STEAM_ID#STEAM_1:}"
if [[ "${STEAM_SUFFIX}" == "${STEAM_ID}" ]]; then
  STEAM_SUFFIX="${STEAM_ID#STEAM_0:}"
fi

COUNT="$(sqlite3 "${DB_PATH}" \
  "SELECT COUNT(*) FROM clutch_team_loadout WHERE steamid LIKE '%${STEAM_SUFFIX}%';")"
echo "--- clutch_team_loadout rows: ${COUNT} ---"
sqlite3 -header -column "${DB_PATH}" \
  "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout WHERE steamid LIKE '%${STEAM_SUFFIX}%' ORDER BY weapon_id;"

if [[ "${COUNT}" -lt 3 ]]; then
  echo ""
  echo "ERROR: expected ≥3 weapon rows (m4, deagle, knife) — team loadout sync broken." >&2
  exit 1
fi

echo ""
echo "OK: clutch_team_loadout populated. In-game: sm_clutch_applyskins"
