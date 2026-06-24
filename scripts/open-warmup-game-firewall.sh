#!/usr/bin/env bash
# Open CS:GO game port for players on the internet (UDP + TCP for RCON).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

PORT="${CSGO_RCON_PORT:-27015}"

echo "Opening game port ${PORT} (UDP + TCP) for all interfaces"

run_ufw() {
  if sudo -n ufw "$@" 2>/dev/null; then
    return 0
  fi
  if ufw "$@" 2>/dev/null; then
    return 0
  fi
  return 1
}

if command -v ufw >/dev/null 2>&1; then
  if run_ufw allow "${PORT}/udp" comment 'clutch csgo game' && \
     run_ufw allow "${PORT}/tcp" comment 'clutch csgo rcon'; then
    run_ufw status numbered 2>/dev/null | grep "${PORT}" || true
    exit 0
  fi
  echo "Could not run ufw (no sudo). As root, run:"
  echo "  sudo ufw allow ${PORT}/udp comment 'clutch csgo game'"
  echo "  sudo ufw allow ${PORT}/tcp comment 'clutch csgo rcon'"
  echo "  sudo ufw status"
  exit 0
fi

echo "ufw not found — open UDP/TCP ${PORT} in your cloud panel or router port-forward"
