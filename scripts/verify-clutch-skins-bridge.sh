#!/usr/bin/env bash
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
SMX="${SM}/plugins/clutch_skins_bridge.smx"
DATA="${SM}/data/clutch_skins.txt"
CORE="${SM}/configs/core.cfg"

echo "=== Clutch Skins Bridge — diagnose ==="
echo ""

if [[ -f "${SMX}" ]]; then
  echo "OK  smx: ${SMX} ($(wc -c < "${SMX}") bytes)"
else
  echo "MISSING smx: ${SMX}"
  echo "  Run: ./scripts/install-clutch-skins-bridge.sh"
fi

if [[ -f "${DATA}" ]]; then
  echo "OK  data: ${DATA} ($(wc -c < "${DATA}") bytes)"
  head -5 "${DATA}"
else
  echo "MISSING data: ${DATA}"
fi

if [[ -f "${CORE}" ]]; then
  echo "OK  core.cfg:"
  grep FollowCSGOServerGuidelines "${CORE}" || echo "  (FollowCSGOServerGuidelines not set)"
else
  echo "MISSING ${CORE}"
fi

echo ""
echo "Recent SM errors (clutch / clutch_skins):"
grep -i clutch "${SM}/logs/errors_"*.log 2>/dev/null | tail -10 || echo "  (none or no log yet)"

echo ""
echo "=== No console do CS (dentro de screen -r) ==="
echo "  sm plugins reload"
echo "  sm plugins load clutch_skins_bridge"
echo "  sm plugins list"
echo "  sm_reloadclutchskins"
echo ""
echo "Se 'sm plugins load' falhar, mande o erro e:"
echo "  tail -30 ${SM}/logs/errors_*.log"
