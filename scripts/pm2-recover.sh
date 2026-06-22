#!/usr/bin/env bash
# Libera porta 3000 e sobe api-csgo com PM2 (uma instância só).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[pm2-recover] Stopping PM2 app api-csgo..."
pm2 delete api-csgo 2>/dev/null || true

if command -v lsof >/dev/null 2>&1; then
  PIDS=$(lsof -ti :3000 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "[pm2-recover] Killing process(es) on port 3000: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
    sleep 1
  fi
elif command -v fuser >/dev/null 2>&1; then
  fuser -k 3000/tcp 2>/dev/null || true
  sleep 1
fi

npm run build
pm2 start ecosystem.config.js --update-env
pm2 save
echo "[pm2-recover] Done. Check: pm2 list && curl -s http://127.0.0.1:3000/health"
