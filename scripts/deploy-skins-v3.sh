#!/usr/bin/env bash
set -euo pipefail

# Deploy completo: api-csgo (build + restart) + plugin v3.
# Rode na VPS como csgo:
#   cd ~/api-csgo && git pull && ./scripts/deploy-skins-v3.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=== api-csgo deploy (skins v3) ==="

if [[ -d .git ]]; then
  echo "Git: $(git rev-parse --short HEAD) on $(git branch --show-current 2>/dev/null || echo '?')"
fi

EXPECTED_VERSION="$(grep -E '#define PLUGIN_VERSION' sourcemod/clutch_skins_bridge.sp | sed 's/.*"\(.*\)".*/\1/')"
echo "Plugin source version: ${EXPECTED_VERSION}"

if [[ ! -f package.json ]]; then
  echo "Not in api-csgo repo" >&2
  exit 1
fi

echo "npm install..."
npm install --no-audit --no-fund

echo "npm run build..."
npm run build

if command -v pm2 >/dev/null 2>&1; then
  echo "pm2 restart..."
  pm2 restart api-csgo 2>/dev/null || pm2 restart all 2>/dev/null || true
else
  echo "pm2 not found — restart api-csgo manually (node dist/index.js)"
fi

echo "Installing SourceMod plugin..."
"${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh"

echo ""
echo "=== Health check ==="
sleep 1
curl -sf "http://127.0.0.1:${PORT:-3000}/health" && echo "" || echo "api-csgo not responding on :${PORT:-3000}"

echo ""
echo "=== Next steps ==="
echo "1. ./scripts/reload-clutch-skins-ingame.sh"
echo "2. In screen: sm plugins info z_clutch_skins_bridge  (must show ${EXPECTED_VERSION})"
echo "3. Equip skin on site → kill in CS"
echo ""
echo "api-csgo .env must include:"
echo "  CSGO_SKINS_SYNC_KEY=..."
echo "  WEAPONS_DB_PATH=/home/csgo/server/csgo/addons/sourcemod/data/sqlite/local.sq3"
echo "  CSGO_RCON_PASSWORD=..."
