#!/usr/bin/env bash
# Start or restart api-csgo in pm2; recover from stale "Process 0 not found" or wrong node on :3000.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 not found" >&2
  exit 1
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"

port_in_use() {
  command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":${PORT} "
}

health_has_gloves_marker() {
  local health
  health="$(curl -sf "${API_URL}/health" 2>/dev/null || true)"
  [[ -n "${health}" ]] && echo "${health}" | grep -q 'glovesPlayerSync'
}

maybe_kill_stale_before_start() {
  if ! port_in_use; then
    return 0
  fi
  if health_has_gloves_marker; then
    return 0
  fi
  echo "[pm2-ensure] :${PORT} in use but /health missing glovesPlayerSync — freeing port before pm2 start"
  bash "${REPO_ROOT}/scripts/kill-stale-api-csgo.sh" || true
}

maybe_kill_stale_before_start

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
  maybe_kill_stale_before_start
  echo "[pm2-ensure] starting api-csgo via ecosystem.config.js"
  pm2 start ecosystem.config.js --update-env
fi

sleep 3

if ! health_has_gloves_marker; then
  echo "[pm2-ensure] /health still missing glovesPlayerSync — running kill-stale and re-starting"
  bash "${REPO_ROOT}/scripts/kill-stale-api-csgo.sh" || true
  pm2 delete api-csgo 2>/dev/null || true
  pm2 start ecosystem.config.js --update-env
  sleep 5
  if ! health_has_gloves_marker; then
    echo "[pm2-ensure] WARN: /health still missing glovesPlayerSync after kill-stale" >&2
    curl -sf "${API_URL}/health" 2>/dev/null || echo "(no /health response)"
    echo ""
    echo "[pm2-ensure] Try: bash scripts/pm2-recover.sh" >&2
    pm2 logs api-csgo --lines 15 --nostream 2>/dev/null || true
  fi
fi

pm2 status api-csgo 2>/dev/null || pm2 list
