#!/usr/bin/env bash
# Pull loadouts from site (curl + optional DNS resolve) → local player-sync (fixed !ws filter).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
JSON_FILE="/tmp/clutch-site-loadouts.json"

echo "=== Sync loadouts (curl → player-sync) ==="
echo "API: ${API_URL}"
echo "DB:  ${DB_PATH}"

bash "${REPO_ROOT}/scripts/fetch-site-loadouts.sh" "${JSON_FILE}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required — sudo apt install jq" >&2
  exit 1
fi

COUNT="$(jq -r '.count // (.loadouts | length) // 0' "${JSON_FILE}")"
echo "Site loadouts: ${COUNT}"

if [[ "${COUNT}" == "0" ]]; then
  echo "WARN: site returned 0 loadouts — equip skins on web panel first"
  jq -r '.loadouts[]? | .steamId as $s | .weapons[]? | "\($s) \(.team // "no-team") \(.weaponId) pk=\(.paintkit)"' \
    "${JSON_FILE}" | head -20 || true
fi

SYNCED=0
ERRORS=0

while IFS= read -r row; do
  STEAM="$(jq -r '.steamId' <<<"${row}")"
  WEAPONS="$(jq -r '.weapons | length' <<<"${row}")"
  BODY="$(jq -c '{steamId, weapons}' <<<"${row}")"
  echo ">>> player-sync ${STEAM} (${WEAPONS} weapons)"
  RESP="$(curl -sf -X POST "${API_URL}/api/csgo/skins/player-sync" \
    -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d "${BODY}" 2>/dev/null || echo '{"error":"request failed"}')"
  if jq -e '.ok == true' <<<"${RESP}" >/dev/null 2>&1; then
    SYNCED=$((SYNCED + 1))
    echo "    OK columns=$(jq -r '.columns // 0' <<<"${RESP}") weapons=$(jq -r '.weapons // 0' <<<"${RESP}")"
  else
    ERRORS=$((ERRORS + 1))
    echo "    FAIL: ${RESP}" >&2
  fi
done < <(jq -c '.loadouts[]?' "${JSON_FILE}")

echo ""
echo "Synced: ${SYNCED} errors: ${ERRORS}"

if [[ -f "${DB_PATH}" ]]; then
  echo ""
  echo ">>> clutch_team_loadout"
  sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS total FROM clutch_team_loadout;"
  sqlite3 "${DB_PATH}" \
    "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout ORDER BY steamid, team, weapon_id LIMIT 40;"
else
  echo "DB not found: ${DB_PATH}"
fi

if [[ "${SYNCED}" -gt 0 ]]; then
  echo ""
  echo "In-game: sm_clutch_applyskins  (or ./scripts/reload-clutch-skins-ingame.sh)"
fi
