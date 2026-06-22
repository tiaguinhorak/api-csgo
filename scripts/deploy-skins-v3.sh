#!/usr/bin/env bash
set -euo pipefail

# Deploy completo: api-csgo (build + restart) + plugin v3.
# Rode na VPS como csgo:
#   cd ~/api-csgo && git pull && ./scripts/deploy-skins-v3.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

chmod +x "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

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
  pm2 restart api-csgo --update-env 2>/dev/null || pm2 restart all --update-env 2>/dev/null || true
else
  echo "pm2 not found — restart api-csgo manually (node dist/index.js)"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" && -z "${API_KEY:-}" ]]; then
  echo ""
  echo "WARN: No CSGO_SKINS_SYNC_KEY or API_KEY in ${REPO_ROOT}/.env"
  echo "  Site push will get HTTP 401. Copy from .env.example and pm2 restart --update-env"
fi

echo "Installing SourceMod plugin..."
chmod +x "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true
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
echo ""
echo "api-csgo .env must include (see .env.example):"
echo "  API_KEY=suachaveapi          # or CSGO_SKINS_SYNC_KEY (site sends both headers)"
echo "  WEAPONS_DB_PATH=/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3"
echo "  CSGO_RCON_PASSWORD=..."
echo ""
echo "After editing .env: pm2 restart api-csgo --update-env"
