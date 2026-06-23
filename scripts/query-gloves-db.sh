#!/usr/bin/env bash
set -euo pipefail

# Lista luvas na SQLite que o CS + api-csgo usam (storage-local / sourcemod-local.sq3).
#
# Uso:
#   ./scripts/query-gloves-db.sh
#   ./scripts/query-gloves-db.sh STEAM_1:0:12345

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
TABLE="${PREFIX}gloves"
FILTER="${1:-}"

echo "=== Gloves SQLite (same DB as !ws / z_clutch_gloves) ==="
echo "DB:   ${DB_PATH}"
echo "Table: ${TABLE}"
echo ""
echo "NOT api-csgo/data/storage-local.sqlite — plugins read SourceMod sqlite only."
echo ""

if [[ ! -f "${DB_PATH}" ]]; then
  echo "ERROR: database file missing." >&2
  echo "Set WEAPONS_DB_PATH in ~/api-csgo/.env (see .env.example)" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "ERROR: sqlite3 not installed" >&2
  exit 1
fi

HAS_TABLE="$(sqlite3 "${DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name='${TABLE}' LIMIT 1;" 2>/dev/null || true)"
if [[ -z "${HAS_TABLE}" ]]; then
  echo "WARN: table '${TABLE}' does not exist yet."
  echo "  Join server once or run: ./scripts/test-gloves-sync.sh STEAM_1:0:YOUR_ID"
  exit 0
fi

echo "--- all rows (steamid, t_group, t_glove, ct_group, ct_glove) ---"
if [[ -n "${FILTER}" ]]; then
  sqlite3 -header -column "${DB_PATH}" \
    "SELECT steamid, t_group, t_glove, t_float, ct_group, ct_glove, ct_float FROM ${TABLE} WHERE steamid LIKE '%${FILTER}%';"
else
  sqlite3 -header -column "${DB_PATH}" \
    "SELECT steamid, t_group, t_glove, t_float, ct_group, ct_glove, ct_float FROM ${TABLE};"
fi
