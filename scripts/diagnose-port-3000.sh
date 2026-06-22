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
pgrep -af "api-csgo|dist/index.js" 2>/dev/null || echo "(no matching node)"
echo ""

echo "--- pm2 list ---"
pm2 list 2>/dev/null || echo "pm2 not running"
echo ""

echo "--- curl health ---"
curl -s -m 2 "http://127.0.0.1:${PORT}/health" || echo "(no response)"
