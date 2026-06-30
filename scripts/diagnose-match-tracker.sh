#!/usr/bin/env bash
# Compare api-csgo live matches vs clutch_match_live SQLite rows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
source_clutch_env "${REPO_ROOT}/.env"

PORT="${PORT:-3001}"
API="http://127.0.0.1:${PORT}"

DB="${CLUTCH_MATCH_DB_PATH:-}"
if [[ -z "${DB}" ]]; then
  DB="$(node -e "const { getMatchLiveDbPath } = require('./dist/services/weapons-db-path'); console.log(getMatchLiveDbPath());" 2>/dev/null || true)"
fi
if [[ -z "${DB}" ]]; then
  DB="/home/csgo/server/csgo/addons/sourcemod/data/sqlite/storage-local.sq3"
fi

echo "=== Clutch match tracker diagnose ==="
echo "API:      ${API}"
echo "SQLite:   ${DB}"
echo ""

echo "--- Live matches (api-csgo) ---"
LIVE_JSON="$(curl -sf "${API}/api/matches?status=live" 2>/dev/null || echo '[]')"
echo "${LIVE_JSON}" | node -e "
const chunks = [];
process.stdin.on('data', (d) => chunks.push(d));
process.stdin.on('end', () => {
  let rows = [];
  try { rows = JSON.parse(Buffer.concat(chunks).toString() || '[]'); } catch { rows = []; }
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log('(none — no status=live in api-csgo)');
    return;
  }
  for (const m of rows) {
    console.log('matchId=' + m.id + ' roomId=' + m.roomId + ' map=' + (m.selectedMap ?? '?'));
  }
});
"

echo ""
echo "--- clutch_match_live (plugin DB) ---"
if [[ ! -f "${DB}" ]]; then
  echo "FAIL: DB not found: ${DB}"
  exit 1
fi

sqlite3 "${DB}" \
  "SELECT match_id, phase, score_team_a, score_team_b, round_num, updated_at FROM clutch_match_live ORDER BY updated_at DESC LIMIT 5;" \
  | while IFS='|' read -r id phase sa sb rnd upd; do
    if [[ -z "${id}" ]]; then
      echo "(empty)"
    else
      echo "match_id=${id} phase=${phase} score=${sa}:${sb} round=${rnd} updated=${upd}"
    fi
  done

echo ""
echo "--- Recent api-csgo logs (match-start / tracker) ---"
pm2 logs api-csgo --lines 120 --nostream 2>&1 | grep -E 'match-start|match-live|match-result|tracker' | tail -20 || echo "(no lines)"

echo ""
echo "If api-csgo has a live match but plugin DB differs, in SERVER console (screen -r):"
echo "  clutch_match_clear"
echo "  clutch_match_begin <matchId-from-api-above> 30"
echo "  clutch_match_roster \"STEAM_A|...\" \"STEAM_B|...\""
echo "After the match: clutch_match_finish  (or play until cs_win_panel_match)"
