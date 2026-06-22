#!/usr/bin/env bash
# Libera porta 3000 e sobe api-csgo com PM2 (uma instância só).
set -euo pipefail
cd "$(dirname "$0")/.."

API_PORT="${PORT:-3000}"

echo "[pm2-recover] Stopping PM2 app api-csgo..."
pm2 delete api-csgo 2>/dev/null || true
sleep 1

echo "[pm2-recover] Freeing port ${API_PORT}..."
for attempt in 1 2 3 4 5; do
  pkill -9 -f "api-csgo/dist/index.js" 2>/dev/null || true
  pkill -9 -f "node.*dist/index.js" 2>/dev/null || true

  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${API_PORT}/tcp" 2>/dev/null || true
  fi

  if command -v lsof >/dev/null 2>&1; then
    PIDS=$(lsof -ti :"${API_PORT}" 2>/dev/null || true)
    if [ -n "${PIDS}" ]; then
      echo "[pm2-recover] attempt ${attempt}: killing PIDs on :${API_PORT}: ${PIDS}"
      kill -9 ${PIDS} 2>/dev/null || true
    fi
  fi

  sleep 1

  if ! lsof -ti :"${API_PORT}" >/dev/null 2>&1; then
    break
  fi
done

if command -v lsof >/dev/null 2>&1 && lsof -ti :"${API_PORT}" >/dev/null 2>&1; then
  echo "[pm2-recover] ERROR: port ${API_PORT} still in use:" >&2
  lsof -i :"${API_PORT}" >&2 || true
  exit 1
fi

npm run build

pm2 start ecosystem.config.js --update-env
sleep 2

if ! curl -sf "http://127.0.0.1:${API_PORT}/health" >/dev/null; then
  echo "[pm2-recover] WARNING: health check failed — check pm2 logs api-csgo" >&2
  pm2 logs api-csgo --lines 15 --nostream 2>/dev/null || true
  exit 1
fi

pm2 save
echo "[pm2-recover] OK — api-csgo online on :${API_PORT}"
pm2 status
