#!/usr/bin/env bash
# Full recovery: build api-csgo, verify routes (skins + stickers), sync from site, show team loadout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=== Clutch fix-all-sync ==="

if [[ -d .git ]]; then
  echo ">>> git pull"
  git pull --ff-only
  echo "At $(git rev-parse --short HEAD)"
fi

chmod +x "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

echo ""
echo ">>> npm install && build"
npm install --no-audit --no-fund
npm run build

if ! grep -q 'player-sync' dist/routes/csgo-stickers-push.js; then
  echo "ERROR: dist missing stickers route — build failed?" >&2
  exit 1
fi

echo ""
bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"

echo ""
echo ">>> pm2 recover (kill stale :PORT, restart api-csgo)"
if bash "${REPO_ROOT}/scripts/pm2-recover.sh"; then
  echo "pm2-recover OK"
else
  echo "pm2-recover failed — trying pm2-ensure..."
  bash "${REPO_ROOT}/scripts/pm2-ensure-api-csgo.sh"
  bash "${REPO_ROOT}/scripts/verify-api-running-build.sh"
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"

echo ""
echo "=== Public checks (what the site hits) ==="
echo "health: $(curl -sf "${API_URL}/health" 2>/dev/null || echo '<fail>')"

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  STICKER_CODE="$(curl -s -o /tmp/clutch-sticker-probe.txt -w '%{http_code}' -X POST \
    "${API_URL}/api/csgo/stickers/player-sync" \
    -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"steamId":"STEAM_1:0:0","entries":[]}' 2>/dev/null || echo "000")"
  echo "stickers/player-sync HTTP ${STICKER_CODE}: $(head -c 120 /tmp/clutch-sticker-probe.txt 2>/dev/null)"
  if [[ "${STICKER_CODE}" == "404" ]]; then
    echo "ERROR: stickers route still 404 — wrong process on :${PORT}. Run: bash scripts/diagnose-port-3000.sh" >&2
    exit 1
  fi
fi

echo ""
bash "${REPO_ROOT}/scripts/sync-team-loadouts-from-site.sh"

DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
echo ""
echo "=== Next steps ==="
echo "1. Site: equip skins on TR tab AND CT tab (different skins per side)"
echo "2. Run this script again OR equip on site to push player-sync"
echo "3. In screen: sm plugins reload z_clutch_skins_bridge  (v3.7.1+)"
echo ""
echo "Plugin: bash scripts/install-clutch-skins-bridge.sh"
echo "Team rows in DB:"
sqlite3 "${DB_PATH}" "SELECT team, weapon_id, paintkit FROM clutch_team_loadout ORDER BY steamid, team LIMIT 20;" 2>/dev/null \
  || echo "(no rows yet)"
