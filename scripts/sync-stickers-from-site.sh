#!/usr/bin/env bash
# Pull ALL player weapon stickers from site Postgres → clutch_weaponstickers SQLite.
#
# Usage:
#   cd ~/api-csgo && bash scripts/sync-stickers-from-site.sh
#   bash scripts/sync-stickers-from-site.sh 203852188   # filter sqlite output

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

STEAM_FRAGMENT="${1:-}"
STICKERS_JSON="/tmp/clutch-site-stickers.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  echo "WARN: CLUTCH_SITE_URL / SITE_ORIGIN missing — running ensure-clutch-site-env.sh"
  bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh" || true
  set -a && source .env && set +a
fi

STICKERS_DB="${STICKERS_DB_PATH:-}"
if [[ -z "${STICKERS_DB}" ]]; then
  WEAPONS_DB="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
  STICKERS_DB="$(dirname "${WEAPONS_DB}")/csgo_weaponstickers.sq3"
fi

echo "=== Sticker sync from site ==="
echo "Site: ${CLUTCH_SITE_URL:-${SITE_ORIGIN:-?}}"
echo "API: ${API_URL}"
echo "Stickers DB: ${STICKERS_DB}"

api_healthy() {
  curl -sf --connect-timeout 3 "${API_URL}/health" >/dev/null 2>&1
}

try_api_sync_from_site() {
  echo ""
  echo ">>> POST ${API_URL}/api/csgo/stickers/sync-from-site"
  local http_code body
  body="$(mktemp)"
  http_code="$(curl -sS --connect-timeout 5 -m 180 \
    -o "${body}" -w '%{http_code}' \
    -X POST "${API_URL}/api/csgo/stickers/sync-from-site" \
    -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/tmp/clutch-sticker-sync-api.err || echo "000")"
  http_code="$(printf '%s' "${http_code}" | tr -d '[:space:]' | tail -c 3)"

  if [[ "${http_code}" == "000" ]]; then
    echo "API unreachable (curl: $(head -c 200 /tmp/clutch-sticker-sync-api.err 2>/dev/null))"
    rm -f "${body}"
    return 1
  fi

  echo "HTTP ${http_code}"
  cat "${body}"
  echo ""

  if [[ "${http_code}" == "200" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.ok == true or (.synced // 0) > 0' "${body}" >/dev/null 2>&1; then
      rm -f "${body}"
      return 0
    fi
  fi

  if [[ "${http_code}" == "200" ]]; then
    rm -f "${body}"
    return 0
  fi

  rm -f "${body}"
  return 1
}

run_direct_import() {
  echo ""
  echo ">>> Fetch stickers JSON from site (curl + optional DNS resolve)"
  bash "${SCRIPT_DIR}/fetch-site-stickers.sh" "${STICKERS_JSON}"

  echo ""
  echo ">>> Import into SQLite (node dist)"
  if [[ ! -f dist/services/stickers-db-sync.js ]]; then
    echo "ERROR: dist missing — run: npm run build" >&2
    exit 1
  fi
  node "${SCRIPT_DIR}/run-import-site-stickers.cjs" "${STICKERS_JSON}"
}

SYNC_OK=0

if api_healthy; then
  if try_api_sync_from_site; then
    SYNC_OK=1
  else
    echo "WARN: API sync-from-site failed — falling back to direct site fetch + SQLite import"
  fi
else
  echo ""
  echo "WARN: api-csgo not responding at ${API_URL}/health"
  echo "  Start: npm run pm2:restart   or   pm2 status"
fi

if [[ "${SYNC_OK}" -eq 0 ]]; then
  run_direct_import
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
  echo "In screen (player alive):"
  echo "  sm_clutch_refresh_stickers \"STEAM_0:0:203852188\""
  echo "Or: sm_clutch_applyskins"
else
  echo "sqlite3 or DB missing: ${STICKERS_DB}"
fi
