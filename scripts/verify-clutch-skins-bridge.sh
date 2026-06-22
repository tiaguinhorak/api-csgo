#!/usr/bin/env bash
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
SMX="${SM}/plugins/z_clutch_skins_bridge.smx"
LEGACY_SMX="${SM}/plugins/clutch_skins_bridge.smx"
DATA="${SM}/data/clutch_skins.txt"
CORE="${SM}/configs/core.cfg"

echo "=== Clutch Skins Bridge — diagnose ==="
echo ""

if [[ -f "${SMX}" ]]; then
  echo "OK  smx: ${SMX} ($(wc -c < "${SMX}") bytes)"
elif [[ -f "${LEGACY_SMX}" ]]; then
  echo "WARN legacy smx only: ${LEGACY_SMX} — run install (need z_clutch_skins_bridge.smx)"
else
  echo "MISSING smx — run: ./scripts/install-clutch-skins-bridge.sh"
fi

if [[ -f "${DATA}" ]]; then
  echo "OK  data: ${DATA} ($(wc -c < "${DATA}") bytes)"
  head -8 "${DATA}"
  if ! grep -q 'STEAM_1:' "${DATA}"; then
    echo "  TIP: re-export from site for STEAM_0 + STEAM_1 keys (or use plugin 1.1.0+)"
  fi
else
  echo "MISSING data: ${DATA}"
fi

if [[ -f "${CORE}" ]]; then
  echo "OK  core.cfg:"
  grep FollowCSGOServerGuidelines "${CORE}" || echo "  (FollowCSGOServerGuidelines not set)"
else
  echo "MISSING ${CORE}"
fi

WEAPONS_SP="${SM}/scripting/weapons.sp"
NATIVES_SP="${SM}/scripting/weapons/natives.sp"
if [[ -f "${WEAPONS_SP}" ]]; then
  if grep -q 'Weapons_ReloadClientData' "${WEAPONS_SP}" && grep -q 'Weapons_ReloadClientData_Native' "${NATIVES_SP}" 2>/dev/null; then
    echo "OK  weapons native patch present in source"
  else
    echo "MISSING Weapons_ReloadClientData in weapons source — run:"
    echo "  CSGO_ROOT=${CSGO_ROOT} bash scripts/patch-weapons-reload-native.sh"
  fi
else
  echo "WARN weapons.sp not found — cannot verify native patch"
fi

echo ""
echo "Recent SM errors (clutch / clutch_skins):"
grep -iE 'clutch|Weapons_ReloadClientData|Native is not bound' "${SM}/logs/errors_"*.log 2>/dev/null | tail -10 || echo "  (none or no log yet)"

echo ""
echo "=== Reload (SSH) ==="
echo "  ./scripts/reload-clutch-skins-ingame.sh"
echo ""
echo "=== Or screen -r (one command per line) ==="
echo "  sm plugins reload z_clutch_skins_bridge"
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
