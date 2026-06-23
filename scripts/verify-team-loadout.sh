#!/usr/bin/env bash
# Show clutch_team_loadout rows for one player (both STEAM_0 / STEAM_1).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

STEAM="${1:-STEAM_1:0:203852188}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"

if [[ ! -f "${DB_PATH}" ]]; then
  echo "DB not found: ${DB_PATH}" >&2
  exit 1
fi

ALT="${STEAM}"
if [[ "${STEAM:6:1}" == "0" ]]; then
  ALT="STEAM_1:${STEAM:8}"
else
  ALT="STEAM_0:${STEAM:8}"
fi

echo "DB: ${DB_PATH}"
echo "steam: ${STEAM} / ${ALT}"
echo ""
sqlite3 "${DB_PATH}" \
  "SELECT COUNT(*) AS team_loadout_rows FROM clutch_team_loadout WHERE steamid IN ('${STEAM}','${ALT}');"
sqlite3 -header -column "${DB_PATH}" \
  "SELECT steamid, team, weapon_id, paintkit, wear FROM clutch_team_loadout WHERE steamid IN ('${STEAM}','${ALT}') ORDER BY team, weapon_id;"
echo ""
sqlite3 -header -column "${DB_PATH}" \
  "SELECT steamid, t_group, t_glove, ct_group, ct_glove FROM gloves WHERE steamid IN ('${STEAM}','${ALT}');"
