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
WEAPONS_SMX="${SM}/plugins/weapons.smx"
if [[ -f "${WEAPONS_SP}" ]]; then
  if grep -q 'Weapons_ReloadClientData' "${WEAPONS_SP}" && grep -q 'Weapons_ReloadClientData_Native' "${NATIVES_SP}" 2>/dev/null; then
    echo "OK  weapons native patch present in source"
    if [[ -f "${WEAPONS_SMX}" ]]; then
      if [[ "${WEAPONS_SP}" -nt "${WEAPONS_SMX}" ]]; then
        echo "WARN weapons.smx is OLDER than weapons.sp — run patch script + reload weapons in CS"
      else
        echo "OK  weapons.smx compiled (smx not older than source)"
      fi
    else
      echo "MISSING ${WEAPONS_SMX} — run patch-weapons-reload-native.sh"
    fi
  else
    echo "MISSING Weapons_ReloadClientData in weapons source — run:"
    echo "  CSGO_ROOT=${CSGO_ROOT} bash scripts/patch-weapons-reload-native.sh"
  fi
else
  echo "WARN weapons.sp not found — cannot verify native patch"
fi

BRIDGE_SMX="${SM}/plugins/z_clutch_skins_bridge.smx"
if [[ -f "${BRIDGE_SMX}" ]]; then
  BRIDGE_MTIME="$(stat -c %Y "${BRIDGE_SMX}" 2>/dev/null || stat -f %m "${BRIDGE_SMX}" 2>/dev/null || echo 0)"
  echo "TIP  bridge smx mtime: $(date -d "@${BRIDGE_MTIME}" 2>/dev/null || date -r "${BRIDGE_MTIME}" 2>/dev/null || echo unknown)"
  echo "     Errors in log BEFORE this time are from an old plugin — reload in CS then respawn."
fi

echo ""
echo "Recent SM errors (last 8 lines — ignore if timestamp is BEFORE bridge reload):"
grep -iE 'clutch|Weapons_ReloadClientData|Native is not bound' "${SM}/logs/errors_"*.log 2>/dev/null | tail -8 || echo "  (none or no log yet)"

echo ""
echo "=== Reload (SSH) ==="
echo "  ./scripts/reload-clutch-skins-ingame.sh"
echo ""
echo "=== Or screen -r (one command per line) ==="
echo "  sm plugins reload z_clutch_skins_bridge"
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
