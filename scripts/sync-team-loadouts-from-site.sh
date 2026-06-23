#!/usr/bin/env bash
# Diagnose + sync CT/TR loadouts from site Postgres into clutch_team_loadout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"

echo "=== Team loadout sync ==="
echo "DB: ${DB_PATH}"
echo "API: ${API_URL}"

if [[ -z "${CLUTCH_SITE_URL:-}" && -z "${SITE_ORIGIN:-}" ]]; then
  echo ""
  echo "WARN: CLUTCH_SITE_URL / SITE_ORIGIN missing — running ensure-clutch-site-env.sh"
  bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"
  set -a && source .env && set +a
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

echo ""
echo ">>> sync-from-site"
RESULT="$(curl -sf -X POST "${API_URL}/api/csgo/skins/sync-from-site" \
  -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" 2>/dev/null || true)"
echo "${RESULT:-<no response>}"

echo ""
echo ">>> clutch_team_loadout rows"
if [[ -f "${DB_PATH}" ]]; then
  sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS total FROM clutch_team_loadout;"
  sqlite3 "${DB_PATH}" "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout ORDER BY steamid, team, weapon_id LIMIT 30;"
else
  echo "DB not found: ${DB_PATH}"
fi

echo ""
echo "In-game: sm plugins reload z_clutch_skins_bridge  (expect v3.7.1+)"
