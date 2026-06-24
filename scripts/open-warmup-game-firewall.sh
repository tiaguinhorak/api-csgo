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

if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow "${PORT}/udp" comment 'clutch csgo game'
  sudo ufw allow "${PORT}/tcp" comment 'clutch csgo rcon'
  sudo ufw status numbered | grep "${PORT}" || true
  exit 0
fi

echo "ufw not found — open UDP/TCP ${PORT} in your cloud panel or router port-forward"
