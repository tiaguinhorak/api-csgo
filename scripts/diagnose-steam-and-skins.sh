#!/usr/bin/env bash
set -euo pipefail

# Diagnóstico rápido: Steam auth + clutch_skins.txt + push api-csgo
#
# Uso na VPS:
#   cd ~/api-csgo && chmod +x scripts/diagnose-steam-and-skins.sh
#   ./scripts/diagnose-steam-and-skins.sh

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
DATA="${CLUTCH_SKINS_OUT:-${CSGO_ROOT}/addons/sourcemod/data/clutch_skins.txt}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:3000}"

echo "=== Steam + Skins diagnose ==="
echo ""

echo "--- 1) clutch_skins.txt ---"
if [[ -f "${DATA}" ]]; then
  echo "OK  ${DATA} ($(wc -c < "${DATA}") bytes)"
  head -20 "${DATA}"
else
  echo "MISSING ${DATA}"
fi

echo ""
echo "--- 2) api-csgo push endpoint ---"
if [[ -z "${SYNC_KEY}" ]]; then
  echo "WARN  CSGO_SKINS_SYNC_KEY not set in shell — export before test"
else
  HTTP="$(curl -sS -o /tmp/clutch-push-test.out -w "%{http_code}" \
    -X POST "${API_URL}/api/csgo/skins/push" \
    -H "x-skins-sync-key: ${SYNC_KEY}" \
    -H "Content-Type: text/plain" \
    --data-binary "test" || echo "000")"
  echo "POST ${API_URL}/api/csgo/skins/push → HTTP ${HTTP}"
  if [[ -f /tmp/clutch-push-test.out ]]; then
    head -c 200 /tmp/clutch-push-test.out; echo
  fi
  if [[ "${HTTP}" == "401" ]]; then
    echo "  → Key mismatch between site .env and api-csgo .env"
  fi
  if [[ "${HTTP}" == "000" ]]; then
    echo "  → api-csgo not running on ${API_URL} (pm2 restart?)"
  fi
fi

echo ""
echo "--- 3) Steam server log (last screen / srcds) ---"
echo "In screen -r, at SERVER START look for:"
echo "  GOOD: 'Logged into Steam game server account' (no error after)"
echo "  BAD:  'Could not establish connection to Steam servers'"
echo ""
echo "If BAD → regenerate GSLT (App 730, IP do VPS) and check outbound firewall."
echo "  https://steamcommunity.com/dev/managegameservers"
echo ""
echo "--- 4) Spawn / map ---"
echo "If log shows: PutClientInServer: no info_player_start"
echo "  In server console: changelevel de_mirage"
echo "  Then: mp_restartgame 1"
echo ""
echo "--- 5) In-game after equip on site ---"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
echo "  kill"
echo ""
echo "Knife test: equip AK/M4 on site (easier than bayonet)."
