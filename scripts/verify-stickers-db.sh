#!/usr/bin/env bash
set -euo pipefail

# Diagnose sticker SQLite tables (clutch_weaponstickers + weaponstickers1).
#
# Usage: cd ~/api-csgo && bash scripts/verify-stickers-db.sh [steam_id_fragment]

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

ALT_DATA_DB="${REPO_ROOT}/data/csgo_weaponstickers.sq3"

echo ">>> Stickers DB (expected): ${STICKERS_DB}"
if [[ -f "${STICKERS_DB}" ]]; then
  ls -la "${STICKERS_DB}" "${STICKERS_DB}"-wal 2>/dev/null || ls -la "${STICKERS_DB}"
  sqlite3 "${STICKERS_DB}" ".tables"
  echo ""
  echo "clutch_weaponstickers count:"
  sqlite3 "${STICKERS_DB}" "SELECT COUNT(*) FROM clutch_weaponstickers;"
  echo "weaponstickers1 count:"
  sqlite3 "${STICKERS_DB}" "SELECT COUNT(*) FROM weaponstickers1;"
  if [[ -n "${STEAM_FRAGMENT}" ]]; then
    echo ""
    echo "clutch_weaponstickers sample (${STEAM_FRAGMENT}):"
    sqlite3 "${STICKERS_DB}" \
      "SELECT steamid, weaponindex, team, slot0, slot1, slot2 FROM clutch_weaponstickers WHERE steamid LIKE '%${STEAM_FRAGMENT}%' LIMIT 20;"
    echo ""
    echo "weaponstickers1 sample (${STEAM_FRAGMENT}):"
    sqlite3 "${STICKERS_DB}" \
      "SELECT steamid, weaponindex, slot0, slot1, slot2 FROM weaponstickers1 WHERE steamid LIKE '%${STEAM_FRAGMENT}%' LIMIT 20;"
  fi
else
  echo "MISSING: ${STICKERS_DB}"
fi

echo ""
if [[ -f "${ALT_DATA_DB}" ]]; then
  echo ">>> WARN: alternate stickers DB found at ${ALT_DATA_DB} (api-csgo may sync here if STICKERS_DB_PATH wrong)"
  sqlite3 "${ALT_DATA_DB}" ".tables" 2>/dev/null || true
  sqlite3 "${ALT_DATA_DB}" "SELECT COUNT(*) FROM clutch_weaponstickers;" 2>/dev/null || true
fi

echo ""
echo ">>> dist build (clutch sync in compiled JS)"
if [[ -f "${REPO_ROOT}/dist/services/stickers-db-sync.js" ]] \
  && grep -q 'clutchStickersTableName' "${REPO_ROOT}/dist/services/stickers-db-sync.js"; then
  echo "OK: dist has clutch_weaponstickers sync"
else
  echo "WARN: dist OUT OF DATE — run: cd ~/api-csgo && npm run build && pm2 restart api-csgo --update-env"
fi

echo ""
echo ">>> Bridge must read SAME file as api-csgo STICKERS_DB_PATH"
echo "    Expected: \${SM}/data/sqlite/csgo_weaponstickers.sq3"
echo "    cfg: clutch_stickers_db_path \"data/sqlite/csgo_weaponstickers.sq3\" (NOT addons/sourcemod/data/...)"

echo ""
echo "Fix wrong path: set STICKERS_DB_PATH=${STICKERS_DB} in api-csgo .env, npm run build, pm2 restart, save stickers on site."
echo "Disable csgo_weaponstickers auto-apply: sm_weaponstickers_enabled 0 in cfg/sourcemod/csgo_weaponstickers.cfg"
echo "Quick migrate TR from legacy: bash scripts/migrate-legacy-stickers-to-clutch.sh ${STEAM_FRAGMENT}"
