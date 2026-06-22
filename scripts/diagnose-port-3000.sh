#!/usr/bin/env bash
# Who is using port 3000? (run on VPS as csgo)
set -uo pipefail

PORT="${PORT:-3000}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Port ${PORT} diagnostics ==="
echo ""

echo "--- ss -tlnp (csgo user) ---"
SS_LINE="$(ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || true)"
if [[ -n "${SS_LINE}" ]]; then
  echo "${SS_LINE}"
  if [[ "${SS_LINE}" != *"pid="* ]]; then
    echo ""
    echo "NOTE: no pid in ss output — port is held by another user (root/www-data)."
    echo "      curl still hits that process; your pm2 api-csgo cannot bind."
    echo "      Fix: sudo bash ${REPO_ROOT}/scripts/fix-port-3000-as-root.sh"
  fi
else
  echo "(nothing on :${PORT})"
fi
echo ""

echo "--- lsof -i :${PORT} (csgo user) ---"
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || echo "(lsof: cannot see listener — likely other user)"
else
  echo "lsof not installed"
fi
echo ""

echo "--- pgrep dist/index.js (any user, visible to csgo) ---"
pgrep -af 'dist/index.js' 2>/dev/null || echo "(none)"
echo ""

echo "--- pgrep node (csgo uid only) ---"
pgrep -u "$(id -u)" -af "api-csgo|dist/index.js|node" 2>/dev/null || echo "(no matching node for csgo)"
echo ""

echo "--- pm2 list (csgo) ---"
pm2 list 2>/dev/null || echo "pm2 not running"
echo ""

echo "--- curl health ---"
HEALTH="$(curl -s -m 2 "http://127.0.0.1:${PORT}/health" || true)"
if [[ -n "${HEALTH}" ]]; then
  echo "${HEALTH}"
  if echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
    echo "(OK: glovesPlayerSync — current api-csgo build is serving :${PORT})"
  else
    echo "(WARN: stale /health — old api on :${PORT}; pm2 api-csgo is crash-looping on EADDRINUSE)"
  fi
else
  echo "(no response)"
fi
echo ""

if ss -tln 2>/dev/null | grep -q ":${PORT} "; then
  echo "--- Suggested fix (no root) ---"
  echo "  cd ~/api-csgo && bash scripts/pm2-recover-no-root.sh"
  echo "  Then update site CSGO_API_URL to http://<vps-ip>:<new-port>"
  echo ""
  echo "--- Suggested fix (with root) ---"
  echo "  sudo bash ${REPO_ROOT}/scripts/fix-port-3000-as-root.sh"
  echo "  cd ~/api-csgo && bash scripts/pm2-recover.sh"
fi
