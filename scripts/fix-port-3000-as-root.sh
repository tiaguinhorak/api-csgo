#!/usr/bin/env bash
# Free TCP :3000 when owned by root/another user (csgo cannot kill it).
#
# Run on VPS as root or via sudo:
#   sudo bash /home/csgo/api-csgo/scripts/fix-port-3000-as-root.sh
#
# Then as csgo:
#   cd ~/api-csgo && bash scripts/pm2-recover.sh

set -euo pipefail

PORT="${PORT:-3000}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root: sudo bash $0" >&2
  exit 1
fi

echo "=== Port ${PORT} (root) ==="
ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || echo "(nothing listening)"

if command -v lsof >/dev/null 2>&1; then
  echo ""
  echo "--- lsof LISTEN ---"
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || echo "(none)"
fi

echo ""
echo "--- pgrep dist/index.js (all users) ---"
pgrep -af 'dist/index.js' 2>/dev/null || echo "(none)"

echo ""
echo "--- root pm2 (if any) ---"
if command -v pm2 >/dev/null 2>&1; then
  pm2 list 2>/dev/null || true
fi

KILLED=0
if command -v lsof >/dev/null 2>&1; then
  while IFS= read -r pid; do
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
      echo "SIGKILL pid ${pid} ($(ps -p "${pid}" -o args= 2>/dev/null || echo '?'))"
      kill -9 "${pid}" 2>/dev/null || true
      KILLED=$((KILLED + 1))
    fi
  done < <(lsof -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true)
fi

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" 2>/dev/null || true
fi

sleep 1

if ss -tln 2>/dev/null | grep -q ":${PORT} "; then
  echo "ERROR: :${PORT} still LISTEN after kill (killed ${KILLED})" >&2
  ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || true
  exit 1
fi

echo "OK: port ${PORT} free (killed ${KILLED} process(es))"
echo "Next: su - csgo -c 'cd ~/api-csgo && bash scripts/pm2-recover.sh'"
