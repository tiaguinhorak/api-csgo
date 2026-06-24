#!/usr/bin/env bash
# Copy weaponstickers1 → clutch_weaponstickers (team T) for bridge per-team reads.
# Run after npm run build if clutch table is empty but legacy has data.
#
# Usage: cd ~/api-csgo && bash scripts/migrate-legacy-stickers-to-clutch.sh [steam_fragment]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEAM_FRAGMENT="${1:-}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

WEAPONS_DB="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
if [[ -n "${STICKERS_DB_PATH:-}" ]]; then
  STICKERS_DB="${STICKERS_DB_PATH}"
else
  STICKERS_DB="$(dirname "${WEAPONS_DB}")/csgo_weaponstickers.sq3"
fi

PREFIX="${STICKERS_TABLE_PREFIX:-}"
LEGACY="${PREFIX}weaponstickers1"
CLUTCH="${PREFIX}clutch_weaponstickers"

echo ">>> Migrate ${LEGACY} → ${CLUTCH} (team T)"
echo "DB: ${STICKERS_DB}"

sqlite3 "${STICKERS_DB}" <<SQL
CREATE TABLE IF NOT EXISTS ${CLUTCH} (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  steamid varchar(64) NOT NULL,
  weaponindex int NOT NULL DEFAULT 0,
  team varchar(2) NOT NULL DEFAULT 'CT',
  slot0 int NOT NULL DEFAULT 0,
  slot1 int NOT NULL DEFAULT 0,
  slot2 int NOT NULL DEFAULT 0,
  slot3 int NOT NULL DEFAULT 0,
  slot4 int NOT NULL DEFAULT 0,
  slot5 int NOT NULL DEFAULT 0,
  wear0 real NOT NULL DEFAULT 0,
  wear1 real NOT NULL DEFAULT 0,
  wear2 real NOT NULL DEFAULT 0,
  wear3 real NOT NULL DEFAULT 0,
  wear4 real NOT NULL DEFAULT 0,
  wear5 real NOT NULL DEFAULT 0,
  last_seen int NOT NULL DEFAULT 0,
  UNIQUE(steamid, weaponindex, team)
);

INSERT INTO ${CLUTCH} (
  steamid, weaponindex, team,
  slot0, slot1, slot2, slot3, slot4, slot5,
  wear0, wear1, wear2, wear3, wear4, wear5
)
SELECT
  steamid, weaponindex, 'T',
  slot0, slot1, slot2, slot3, slot4, slot5,
  wear0, wear1, wear2, wear3, wear4, wear5
FROM ${LEGACY}
WHERE (slot0 != 0 OR slot1 != 0 OR slot2 != 0 OR slot3 != 0 OR slot4 != 0 OR slot5 != 0)
  ${STEAM_FRAGMENT:+AND steamid LIKE '%${STEAM_FRAGMENT}%'}
ON CONFLICT(steamid, weaponindex, team) DO UPDATE SET
  slot0=excluded.slot0, slot1=excluded.slot1, slot2=excluded.slot2,
  slot3=excluded.slot3, slot4=excluded.slot4, slot5=excluded.slot5,
  wear0=excluded.wear0, wear1=excluded.wear1, wear2=excluded.wear2,
  wear3=excluded.wear3, wear4=excluded.wear4, wear5=excluded.wear5;
SQL

sqlite3 "${STICKERS_DB}" "PRAGMA wal_checkpoint(TRUNCATE);"

echo "clutch_weaponstickers count: $(sqlite3 "${STICKERS_DB}" "SELECT COUNT(*) FROM ${CLUTCH};")"
if [[ -n "${STEAM_FRAGMENT}" ]]; then
  sqlite3 "${STICKERS_DB}" \
    "SELECT steamid, weaponindex, team, slot0, slot1 FROM ${CLUTCH} WHERE steamid LIKE '%${STEAM_FRAGMENT}%';"
fi

echo ""
echo "TR stickers migrated from legacy. Configure CT stickers on site and save (after npm run build)."
