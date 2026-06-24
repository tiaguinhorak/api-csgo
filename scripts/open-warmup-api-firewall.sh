#!/usr/bin/env bash
# Allow site dev (LAN) to POST player-sync to warmup api-csgo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3001}"
SUBNET="${WARMUP_API_LAN_SUBNET:-192.168.100.0/24}"
PUBLIC="${WARMUP_API_PUBLIC:-0}"

if [[ "${PUBLIC}" == "1" ]]; then
  echo "Opening TCP ${PORT} for ALL (site on Hostinger / internet)"
  if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "${PORT}/tcp" comment 'clutch api-csgo public'
    sudo ufw status numbered | grep "${PORT}" || true
    exit 0
  fi
  echo "ufw not found — open TCP ${PORT} in cloud firewall"
  exit 0
fi

echo "Opening TCP ${PORT} for ${SUBNET} (api-csgo warmup push from site LAN only)"

if command -v ufw >/dev/null 2>&1; then
  if sudo -n ufw status 2>/dev/null | grep -qi inactive; then
    echo "ufw inactive — no rule needed"
    exit 0
  fi
  if sudo -n ufw allow from "${SUBNET}" to any port "${PORT}" proto tcp comment 'clutch api-csgo' 2>/dev/null; then
    echo "OK: ufw rule added"
    sudo -n ufw status numbered 2>/dev/null | grep "${PORT}" || true
    exit 0
  fi
  echo "WARN: could not run ufw without sudo — as root:"
  echo "  sudo ufw allow from ${SUBNET} to any port ${PORT} proto tcp comment 'clutch api-csgo'"
  exit 0
fi

echo "ufw not found — if push fails from site, open port ${PORT} manually for ${SUBNET}"
