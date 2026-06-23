#!/usr/bin/env bash
# Creates clutch_team_loadout in the weapons SQLite DB (same file as kgns !ws).
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
PREFIX="${WEAPONS_TABLE_PREFIX:-}"
TABLE="${PREFIX}clutch_team_loadout"

if [[ ! -f "${DB_PATH}" ]]; then
  echo "ERROR: DB not found: ${DB_PATH}" >&2
  echo "Set WEAPONS_DB_PATH in api-csgo/.env" >&2
  exit 1
fi

sqlite3 "${DB_PATH}" <<EOF
CREATE TABLE IF NOT EXISTS ${TABLE} (
  steamid varchar(32) NOT NULL,
  team char(2) NOT NULL,
  weapon_id varchar(64) NOT NULL,
  paintkit int NOT NULL DEFAULT 0,
  wear real NOT NULL DEFAULT 0.15,
  seed int NOT NULL DEFAULT 0,
  stattrak int NOT NULL DEFAULT 0,
  stattrak_count int NOT NULL DEFAULT 0,
  nametag varchar(64) NOT NULL DEFAULT '',
  knife_index int NOT NULL DEFAULT -1,
  PRIMARY KEY (steamid, team, weapon_id)
);
EOF

echo "OK: table ${TABLE} ready in ${DB_PATH}"
sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS rows FROM ${TABLE};"
