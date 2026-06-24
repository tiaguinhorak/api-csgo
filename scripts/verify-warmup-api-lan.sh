#!/usr/bin/env bash
# Confirm api-csgo listens on LAN (site dev must reach warmup :PORT).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/pm2-local.sh"

echo "=== Warmup API LAN check ==="
echo "PORT=${PORT}"
echo "BIND_HOST=${BIND_HOST:-0.0.0.0 (default)}"

if grep -qE '^BIND_HOST=127' .env 2>/dev/null; then
  echo "ERROR: BIND_HOST=127.0.0.1 blocks site push from another host." >&2
  echo "  Fix: BIND_HOST=0.0.0.0 in .env && pm2 restart api-csgo --update-env" >&2
  exit 1
fi

echo ""
echo "--- TCP listeners on :${PORT} ---"
if command -v ss >/dev/null 2>&1; then
  ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || echo "(no listener on :${PORT})"
else
  netstat -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || true
fi

echo ""
echo "--- local health ---"
curl -sf "${CLUTCH_API_URL}/health" && echo "" || echo "FAIL: no response on ${CLUTCH_API_URL}"

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -n "${LAN_IP}" ]]; then
  echo ""
  echo "--- LAN health (${LAN_IP}) ---"
  if curl -sf --max-time 3 "http://${LAN_IP}:${PORT}/health" >/dev/null; then
    echo "OK: http://${LAN_IP}:${PORT}/health"
  else
    echo "FAIL: cannot reach http://${LAN_IP}:${PORT}/health from this host"
    echo "  Check firewall: bash scripts/open-warmup-api-firewall.sh"
  fi
  echo ""
  echo "On site host (192.168.100.6) run:"
  echo "  curl -s http://${LAN_IP}:${PORT}/health"
fi
