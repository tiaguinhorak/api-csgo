#!/usr/bin/env bash
# Libera porta e sobe api-csgo com PM2 (uma instância só).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/pm2-local.sh"

echo "[pm2-recover] Stopping PM2 daemon and all apps..."
pm2 delete api-csgo 2>/dev/null || true
pm2 kill 2>/dev/null || true
sleep 2

echo "[pm2-recover] Killing stray api-csgo node (not managed by pm2)..."
if ! bash scripts/kill-stale-api-csgo.sh; then
  stale_rc=$?
  if [[ "${stale_rc}" -eq 2 ]]; then
    echo "[pm2-recover] Port ${API_PORT} held by another user — cannot recover as csgo." >&2
    echo "Run: bash ${REPO_ROOT}/scripts/pm2-recover-no-root.sh" >&2
    echo "Or (needs root): sudo bash ${REPO_ROOT}/scripts/fix-port-3000-as-root.sh" >&2
    exit 2
  fi
fi

npm run build

if ! grep -q 'player-sync' dist/routes/csgo-stickers-push.js 2>/dev/null; then
  echo "[pm2-recover] ERROR: dist missing stickers player-sync route" >&2
  exit 1
fi

echo "[pm2-recover] Starting api-csgo via pm2 on :${API_PORT}..."
pm2 start ecosystem.config.js --update-env
sleep 5

HEALTH="$(curl -sf "${CLUTCH_API_URL}/health" 2>/dev/null || true)"
if [[ -z "${HEALTH}" ]]; then
  echo "[pm2-recover] health check failed:" >&2
  pm2 logs api-csgo --lines 20 --nostream 2>/dev/null || true
  exit 1
fi
if ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
  echo "[pm2-recover] WARN: /health missing glovesPlayerSync (stale listener?)" >&2
  echo "${HEALTH}" >&2
  if bash scripts/kill-stale-api-csgo.sh; then
    pm2 delete api-csgo 2>/dev/null || true
    pm2 start ecosystem.config.js --update-env
    sleep 5
    HEALTH="$(curl -sf "${CLUTCH_API_URL}/health" 2>/dev/null || true)"
  else
    stale_rc=$?
    if [[ "${stale_rc}" -eq 2 ]]; then
      echo "[pm2-recover] Run: bash ${REPO_ROOT}/scripts/pm2-recover-no-root.sh" >&2
      echo "Or (needs root): sudo bash ${REPO_ROOT}/scripts/fix-port-3000-as-root.sh" >&2
      exit 2
    fi
  fi
  if [[ -z "${HEALTH}" ]] || ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
    echo "[pm2-recover] health still wrong after kill-stale:" >&2
    echo "${HEALTH:-<no response>}" >&2
    echo "[pm2-recover] Run: bash scripts/diagnose-port-3000.sh" >&2
    pm2 logs api-csgo --lines 20 --nostream 2>/dev/null || true
    exit 1
  fi
fi

if ! echo "${HEALTH}" | grep -q 'stickersPlayerSync'; then
  echo "[pm2-recover] WARN: /health missing stickersPlayerSync — old build still on :${API_PORT}?" >&2
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
curl -s "${CLUTCH_API_URL}/health"
echo ""
