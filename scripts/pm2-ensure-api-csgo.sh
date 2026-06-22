#!/usr/bin/env bash
# Start or restart api-csgo in pm2; recover from stale "Process 0 not found".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 not found" >&2
  exit 1
fi

restart_ok=0
if pm2 describe api-csgo >/dev/null 2>&1; then
  if pm2 restart api-csgo --update-env; then
    restart_ok=1
  else
    echo "[pm2-ensure] restart failed (stale pm2 entry?) — deleting and re-registering api-csgo"
    pm2 delete api-csgo 2>/dev/null || true
  fi
fi

if [[ "${restart_ok}" -eq 0 ]]; then
  echo "[pm2-ensure] starting api-csgo via ecosystem.config.js"
  pm2 start ecosystem.config.js --update-env
fi

sleep 2
pm2 status api-csgo 2>/dev/null || pm2 list
