#!/usr/bin/env bash
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"

detect_live_csgo_root() {
  local pid cwd exe dir
  pid="$(pgrep -n -x srcds_linux 2>/dev/null || pgrep -n -f 'srcds_linux.*csgo' 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
  if [[ -n "${cwd}" && -d "${cwd}/addons/sourcemod/plugins" ]]; then
    echo "${cwd}"
    return 0
  fi
  exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
  dir="$(dirname "${exe}")"
  if [[ -d "${dir}/csgo/addons/sourcemod/plugins" ]]; then
    echo "${dir}/csgo"
    return 0
  fi
  if [[ -d "${dir}/addons/sourcemod/plugins" ]]; then
    echo "${dir}"
    return 0
  fi
  return 1
}

LIVE_ROOT="$(detect_live_csgo_root || true)"
if [[ -n "${LIVE_ROOT}" && "${LIVE_ROOT}" != "${CSGO_ROOT}" ]]; then
  echo "WARN: default CSGO_ROOT=${CSGO_ROOT} but srcds runs from ${LIVE_ROOT}"
  CSGO_ROOT="${LIVE_ROOT}"
fi

SM="${CSGO_ROOT}/addons/sourcemod"
BRIDGE_SMX="${SM}/plugins/z_clutch_skins_bridge.smx"
GLOVES_SMX="${SM}/plugins/z_clutch_gloves.smx"
LEGACY_SMX="${SM}/plugins/clutch_skins_bridge.smx"
DATA="${SM}/data/clutch_skins.txt"
CORE="${SM}/configs/core.cfg"

echo "=== Clutch plugins — diagnose ==="
echo "CSGO_ROOT: ${CSGO_ROOT}"
if [[ -n "${LIVE_ROOT}" ]]; then
  echo "srcds live:  ${LIVE_ROOT}"
else
  echo "srcds live:  (not running)"
fi
echo ""

if [[ -f "${GLOVES_SMX}" ]]; then
  echo "OK  ${GLOVES_SMX} ($(wc -c < "${GLOVES_SMX}") bytes)"
else
  echo "MISSING ${GLOVES_SMX} — run: ./scripts/install-clutch-skins-bridge.sh"
fi

if [[ -f "${BRIDGE_SMX}" ]]; then
  echo "OK  ${BRIDGE_SMX} ($(wc -c < "${BRIDGE_SMX}") bytes)"
elif [[ -f "${LEGACY_SMX}" ]]; then
  echo "WARN legacy smx only: ${LEGACY_SMX} — need z_clutch_skins_bridge.smx"
else
  echo "MISSING ${BRIDGE_SMX} — run: ./scripts/install-clutch-skins-bridge.sh"
fi

if [[ -f "${DATA}" ]]; then
  echo "OK  data: ${DATA} ($(wc -c < "${DATA}") bytes) (v3+ uses weapons DB, not this file)"
else
  echo "NOTE: ${DATA} missing (OK if using weapons DB only)"
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
        echo "OK  weapons.smx compiled"
      fi
    else
      echo "MISSING ${WEAPONS_SMX}"
    fi
  else
    echo "MISSING Weapons_ReloadClientData in weapons source"
  fi
else
  echo "WARN weapons.sp not found"
fi

if [[ -f "${BRIDGE_SMX}" ]]; then
  BRIDGE_MTIME="$(stat -c %Y "${BRIDGE_SMX}" 2>/dev/null || stat -f %m "${BRIDGE_SMX}" 2>/dev/null || echo 0)"
  echo "TIP  bridge smx mtime: $(date -d "@${BRIDGE_MTIME}" 2>/dev/null || date -r "${BRIDGE_MTIME}" 2>/dev/null || echo unknown)"
fi

echo ""
echo "Recent SM errors (clutch / gloves):"
grep -iE 'clutch|ClutchGloves|z_clutch' "${SM}/logs/errors_"*.log 2>/dev/null | tail -12 || echo "  (none or no log yet)"

echo ""
echo "=== In-game (screen -r) — if plugins 'not loaded', use LOAD not reload ==="
echo "  sm plugins load z_clutch_gloves"
echo "  sm plugins load z_clutch_skins_bridge"
echo "  sm plugins info z_clutch_gloves"
echo "  sm plugins info z_clutch_skins_bridge"
echo ""
echo "=== Or from SSH ==="
echo "  ./scripts/install-clutch-skins-bridge.sh"
echo "  ./scripts/reload-clutch-skins-ingame.sh"
