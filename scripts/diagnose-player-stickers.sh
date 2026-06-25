#!/usr/bin/env bash
# Show sticker rows in VPS SQLite (compare with site inventory).
#
# Usage:
#   bash scripts/diagnose-player-stickers.sh STEAM_0:0:203852188
#   bash scripts/diagnose-player-stickers.sh 203852188

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

RAW="${1:-203852188}"
STEAM_FILTER="${RAW}"
if [[ "${RAW}" != STEAM_* ]]; then
  STEAM_FILTER="STEAM_0:0:${RAW}"
fi

DB="${STICKERS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/csgo_weaponstickers.sq3}"
PREFIX="${STICKERS_TABLE_PREFIX:-}"
TABLE="${PREFIX}clutch_weaponstickers"
LEGACY="${PREFIX}weaponstickers1"

if [[ ! -f "${DB}" ]]; then
  echo "ERROR: stickers DB not found: ${DB}" >&2
  exit 1
fi

echo "=== Sticker DB diagnose ==="
echo "DB:   ${DB}"
echo "Steam filter: ${STEAM_FILTER}"
echo ""

echo "--- ${TABLE} (bridge reads this — per team) ---"
sqlite3 -header -column "${DB}" \
  "SELECT weaponindex, team, slot0, slot1, slot2, slot3, last_seen
   FROM ${TABLE}
   WHERE steamid LIKE '%${STEAM_FILTER}%'
   ORDER BY weaponindex, team;"

echo ""
echo "--- ${LEGACY} (should be empty or mirror current team only) ---"
sqlite3 -header -column "${DB}" \
  "SELECT weaponindex, slot0, slot1, slot2, slot3, last_seen
   FROM ${LEGACY}
   WHERE steamid LIKE '%${STEAM_FILTER}%'
   ORDER BY weaponindex;"

echo ""
echo "Weapon defindex ref: 9=AWP, 7=AK, 1=Deagle"
echo "If rows differ from site → push from dev PC:"
echo "  bash scripts/push-stickers-dev-to-vps.sh"
echo "Then in-game: sm_clutch_refresh_stickers \"${STEAM_FILTER}\""
