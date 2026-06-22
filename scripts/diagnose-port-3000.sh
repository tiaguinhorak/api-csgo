#!/usr/bin/env bash
# Who is using port 3000? (run on VPS as csgo)
set -uo pipefail

PORT="${PORT:-3000}"
echo "=== Port ${PORT} diagnostics ==="
echo ""

echo "--- ss -tlnp ---"
ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || echo "(nothing on :${PORT})"
echo ""

echo "--- lsof -i :${PORT} ---"
if command -v lsof >/dev/null 2>&1; then
  lsof -i :"${PORT}" 2>/dev/null || echo "(lsof: nothing)"
else
  echo "lsof not installed"
fi
echo ""

echo "--- pgrep node (api-csgo) ---"
pgrep -u "$(id -u)" -af "api-csgo|dist/index.js" 2>/dev/null || echo "(no matching node)"
echo ""

echo "--- pm2 list ---"
pm2 list 2>/dev/null || echo "pm2 not running"
echo ""

echo "--- curl health ---"
curl -s -m 2 "http://127.0.0.1:${PORT}/health" || echo "(no response)"
echo ""

if ss -tln 2>/dev/null | grep -q ":${PORT} "; then
  if ! pm2 list 2>/dev/null | grep -q api-csgo; then
    echo "--- FIX: stray node on :${PORT} (not in pm2) ---"
    echo "  ./scripts/kill-stale-api-csgo.sh"
    echo "  pm2 start ecosystem.config.js --update-env && pm2 save"
    echo "  Or: kill -9 \$(pgrep -u \$(id -u) -f 'api-csgo/dist/index.js')"
  fi
fi
