#!/usr/bin/env bash
# Start api-csgo on a free port when :3000 is held by another user (no sudo).
#
# Uso na VPS (usuário csgo):
#   cd ~/api-csgo && git pull && bash scripts/pm2-recover-no-root.sh
#
# Depois atualize no site (Hostinger .env):
#   CSGO_API_URL=http://188.220.168.233:<PORTA>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

SCRIPTS_DIR="${REPO_ROOT}/scripts"
chmod +x "${SCRIPTS_DIR}/"*.sh 2>/dev/null || true

set_env_port() {
  local port="$1"
  if [[ ! -f .env ]]; then
    cp .env.example .env 2>/dev/null || touch .env
  fi
  if grep -q '^PORT=' .env; then
    sed -i "s/^PORT=.*/PORT=${port}/" .env
  else
    echo "PORT=${port}" >> .env
  fi
  if grep -q '^CLUTCH_API_URL=' .env; then
    sed -i "s/^CLUTCH_API_URL=.*/CLUTCH_API_URL=http://127.0.0.1:${port}/" .env
  else
    echo "CLUTCH_API_URL=http://127.0.0.1:${port}" >> .env
  fi
}

echo "[no-root] Port 3000 is often held by another user's process on shared VPS."
echo "[no-root] Finding a free port for api-csgo (3001-3099)..."

FREE_PORT="$(bash "${SCRIPTS_DIR}/find-free-api-port.sh" 3001 3099)"
echo "[no-root] Using PORT=${FREE_PORT}"

set_env_port "${FREE_PORT}"

set -a
# shellcheck disable=SC1091
source .env
set +a

export PORT="${FREE_PORT}"

pm2 delete api-csgo 2>/dev/null || true

npm run build

if ! grep -q 'glovesPlayerSync' dist/index.js; then
  echo "[no-root] ERROR: dist/index.js missing glovesPlayerSync — git pull && npm run build" >&2
  exit 1
fi

echo "[no-root] Starting pm2 on :${PORT}..."
pm2 start ecosystem.config.js --update-env
sleep 4

API_URL="http://127.0.0.1:${PORT}"
HEALTH="$(curl -sf "${API_URL}/health" 2>/dev/null || true)"

if [[ -z "${HEALTH}" ]] || ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
  echo "[no-root] ERROR: api not healthy on :${PORT}" >&2
  echo "${HEALTH:-<no response>}" >&2
  pm2 logs api-csgo --lines 25 --nostream 2>/dev/null || true
  exit 1
fi

pm2 save

PUBLIC_IP="${CLUTCH_PUBLIC_IP:-}"
if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="$(curl -sf --max-time 3 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="188.220.168.233"
fi

echo ""
echo "=== OK — api-csgo on port ${PORT} ==="
echo "health: ${HEALTH}"
pm2 status api-csgo 2>/dev/null || pm2 list
echo ""
echo ">>> Atualize o site (Hostinger / produção) .env:"
echo "CSGO_API_URL=http://${PUBLIC_IP}:${PORT}"
echo ""
echo "Teste local:"
echo "  curl -s http://127.0.0.1:${PORT}/health"
echo "  PORT=${PORT} bash scripts/test-gloves-sync.sh STEAM_1:0:203852188"
