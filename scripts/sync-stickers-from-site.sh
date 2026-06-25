#!/usr/bin/env bash
# Pull ALL player weapon stickers from site Postgres → clutch_weaponstickers SQLite.
# Run on ranked VPS after site sticker changes if push from Hostinger failed.
#
# Usage:
#   cd ~/api-csgo && bash scripts/sync-stickers-from-site.sh
#   bash scripts/sync-stickers-from-site.sh 203852188   # show rows for steam fragment

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

STEAM_FRAGMENT="${1:-}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

if [[ -z "${CLUTCH_SITE_URL:-}" && -z "${SITE_ORIGIN:-}" ]]; then
  echo "WARN: CLUTCH_SITE_URL / SITE_ORIGIN missing — run: bash scripts/ensure-clutch-site-env.sh"
  bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh" || true
  set -a && source .env && set +a
fi

STICKERS_DB="${STICKERS_DB_PATH:-}"
if [[ -z "${STICKERS_DB}" ]]; then
  WEAPONS_DB="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
  STICKERS_DB="$(dirname "${WEAPONS_DB}")/csgo_weaponstickers.sq3"
fi

echo "=== Sticker sync from site ==="
echo "API: ${API_URL}"
echo "Stickers DB: ${STICKERS_DB}"

echo ""
echo ">>> POST ${API_URL}/api/csgo/stickers/sync-from-site"
RESP="$(curl -sf -X POST "${API_URL}/api/csgo/stickers/sync-from-site" \
  -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d '{}' 2>&1)" || {
  echo "ERROR: sync-from-site failed: ${RESP}" >&2
  exit 1
}

echo "${RESP}"

if command -v jq >/dev/null 2>&1; then
  SYNCED="$(echo "${RESP}" | jq -r '.synced // 0')"
  echo "Players synced: ${SYNCED}"
fi

echo ""
echo ">>> clutch_weaponstickers sample"
if [[ -f "${STICKERS_DB}" ]] && command -v sqlite3 >/dev/null 2>&1; then
  WHERE=""
  if [[ -n "${STEAM_FRAGMENT}" ]]; then
    WHERE="WHERE steamid LIKE '%${STEAM_FRAGMENT}%'"
  fi
  sqlite3 -header -column "${STICKERS_DB}" \
    "SELECT steamid, weaponindex, team, slot0, slot1, slot2, slot3, last_seen FROM clutch_weaponstickers ${WHERE} ORDER BY last_seen DESC LIMIT 40;"
  echo ""
  echo "In screen (player alive): sm_clutch_refresh_stickers"
  echo "Or full apply: sm_clutch_applyskins"
else
  echo "sqlite3 or DB missing: ${STICKERS_DB}"
fi
