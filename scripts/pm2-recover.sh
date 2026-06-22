#!/usr/bin/env bash
# Libera porta 3000 e sobe api-csgo com PM2 (uma instância só).
set -euo pipefail
cd "$(dirname "$0")/.."

API_PORT="${PORT:-3000}"

echo "[pm2-recover] Stopping PM2 daemon and all apps..."
pm2 delete api-csgo 2>/dev/null || true
pm2 kill 2>/dev/null || true
sleep 2

echo "[pm2-recover] Killing stray api-csgo node (not managed by pm2)..."
bash scripts/kill-stale-api-csgo.sh

npm run build

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "[pm2-recover] ERROR: dist missing gloves sync in player-sync route" >&2
  exit 1
fi

echo "[pm2-recover] Starting api-csgo via pm2..."
pm2 start ecosystem.config.js --update-env
sleep 5

HEALTH="$(curl -sf "http://127.0.0.1:${API_PORT}/health" 2>/dev/null || true)"
if [[ -z "${HEALTH}" ]]; then
  echo "[pm2-recover] health check failed:" >&2
  pm2 logs api-csgo --lines 20 --nostream 2>/dev/null || true
  exit 1
fi
if ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
  echo "[pm2-recover] WARN: /health missing glovesPlayerSync (stale listener?)" >&2
  echo "${HEALTH}" >&2
  bash scripts/kill-stale-api-csgo.sh || true
  pm2 delete api-csgo 2>/dev/null || true
  pm2 start ecosystem.config.js --update-env
  sleep 5
  HEALTH="$(curl -sf "http://127.0.0.1:${API_PORT}/health" 2>/dev/null || true)"
  if [[ -z "${HEALTH}" ]] || ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
    echo "[pm2-recover] health still wrong after kill-stale:" >&2
    echo "${HEALTH:-<no response>}" >&2
    pm2 logs api-csgo --lines 20 --nostream 2>/dev/null || true
    exit 1
  fi
fi

if [[ -f scripts/verify-api-running-build.sh ]]; then
  if ! bash scripts/verify-api-running-build.sh; then
    echo "[pm2-recover] verify failed after start" >&2
    pm2 logs api-csgo --lines 30 --nostream 2>/dev/null || true
    exit 1
  fi
else
  echo "[pm2-recover] WARN: verify-api-running-build.sh missing — pull latest api-csgo for auto-verify"
fi

pm2 save

echo "[pm2-recover] OK"
pm2 status
curl -s "http://127.0.0.1:${API_PORT}/health"
echo ""
