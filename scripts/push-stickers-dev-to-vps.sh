#!/usr/bin/env bash
# Push weapon stickers from LOCAL site (npm run dev) → ranked VPS api-csgo SQLite.
#
# Use when production site is NOT live — VPS cannot curl clutchclube.com.br.
#
# On your PC (site running at http://127.0.0.1:3000):
#   cd api-csgo
#   # .env: CSGO_SKINS_SYNC_KEY + CSGO_API_URL=http://YOUR_VPS_PUBLIC_IP:3001
#   bash scripts/push-stickers-dev-to-vps.sh
#
# Optional: push one player only
#   bash scripts/push-stickers-dev-to-vps.sh STEAM_0:0:203852188

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

STEAM_FILTER="${1:-}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DEV_SITE="${CLUTCH_DEV_SITE_URL:-${CLUTCH_SITE_LAN_URL:-http://127.0.0.1:3000}}"
DEV_SITE="${DEV_SITE%/}"
VPS_API="${CSGO_API_URL:-}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set (must match site/.env)" >&2
  exit 1
fi

if [[ -z "${VPS_API}" ]]; then
  echo "ERROR: CSGO_API_URL not set — ranked VPS public URL, e.g. http://188.220.168.233:3001" >&2
  exit 1
fi

VPS_API="${VPS_API%/}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (apt install jq / brew install jq)" >&2
  exit 1
fi

JSON_FILE="/tmp/clutch-dev-stickers-equipped.json"

echo "=== Push stickers dev → VPS ==="
echo "Local site: ${DEV_SITE}"
echo "VPS API:    ${VPS_API}"
echo ""

echo ">>> GET ${DEV_SITE}/api/csgo/stickers/equipped"
HTTP_CODE="$(curl -sS --connect-timeout 10 -m 120 \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Accept: application/json" \
  -o "${JSON_FILE}" \
  -w '%{http_code}' \
  "${DEV_SITE}/api/csgo/stickers/equipped" 2>/tmp/clutch-dev-stickers.err || echo "000")"

HTTP_CODE="$(printf '%s' "${HTTP_CODE}" | tr -d '[:space:]' | tail -c 3)"
echo "HTTP ${HTTP_CODE}"

if [[ "${HTTP_CODE}" == "000" ]]; then
  echo "curl error: $(cat /tmp/clutch-dev-stickers.err 2>/dev/null)" >&2
  echo "" >&2
  echo "Start site on your PC: cd site && npm run dev" >&2
  exit 1
fi

if [[ "${HTTP_CODE}" != "200" ]]; then
  head -c 400 "${JSON_FILE}" 2>/dev/null || true
  echo "" >&2
  echo "ERROR: site stickers API failed (HTTP ${HTTP_CODE}) — check CSGO_SKINS_SYNC_KEY matches site" >&2
  exit 1
fi

COUNT="$(jq -r '.stickers | length // 0' "${JSON_FILE}")"
echo "Players with sticker rows: ${COUNT}"

if [[ "${COUNT}" == "0" ]]; then
  echo "WARN: no stickers on local site — equip stickers in inventory UI first"
  exit 0
fi

SYNCED=0
ERRORS=0

while IFS= read -r row; do
  STEAM="$(jq -r '.steamId' <<<"${row}")"
  if [[ -n "${STEAM_FILTER}" && "${STEAM}" != *"${STEAM_FILTER}"* ]]; then
    continue
  fi
  ENTRIES="$(jq -r '.entries | length' <<<"${row}")"
  BODY="$(jq -c '{steamId, entries}' <<<"${row}")"
  echo ">>> POST player-sync ${STEAM} (${ENTRIES} weapons)"
  RESP="$(curl -sS --connect-timeout 15 -m 120 \
    -X POST "${VPS_API}/api/csgo/stickers/player-sync" \
    -H "x-skins-sync-key: ${SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d "${BODY}" 2>/tmp/clutch-dev-push.err || echo '{"error":"request failed"}')"
  if jq -e '.ok == true' <<<"${RESP}" >/dev/null 2>&1; then
    SYNCED=$((SYNCED + 1))
    echo "    OK updated=$(jq -r '.updated // 0' <<<"${RESP}") clutchRows=$(jq -r '.clutchRows // 0' <<<"${RESP}")"
  else
    ERRORS=$((ERRORS + 1))
    echo "    FAIL: ${RESP}" >&2
    if [[ -s /tmp/clutch-dev-push.err ]]; then
      echo "    $(head -c 200 /tmp/clutch-dev-push.err)" >&2
    fi
  fi
done < <(jq -c '.stickers[]?' "${JSON_FILE}")

echo ""
echo "Pushed: ${SYNCED} errors: ${ERRORS}"

if [[ "${SYNCED}" -gt 0 ]]; then
  echo ""
  echo "On VPS screen (player alive):"
  echo "  sm_clutch_refresh_stickers \"STEAM_0:0:203852188\""
fi
