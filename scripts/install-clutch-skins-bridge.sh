#!/usr/bin/env bash
set -euo pipefail

# Instala e compila clutch_skins_bridge na VPS (rode como csgo na máquina do CS).
#
# Uso:
#   cd ~/api-csgo && git pull
#   ./scripts/install-clutch-skins-bridge.sh
#   (ou: bash scripts/install-clutch-skins-bridge.sh)

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
  echo "srcds is running from ${LIVE_ROOT} (not default ${CSGO_ROOT}) — installing there."
  CSGO_ROOT="${LIVE_ROOT}"
fi

SM="${CSGO_ROOT}/addons/sourcemod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SP_SRC="${REPO_ROOT}/sourcemod/clutch_skins_bridge.sp"
CFG_SRC="${REPO_ROOT}/sourcemod/clutch_skins_bridge.cfg"
OVERRIDES_SRC="${REPO_ROOT}/sourcemod/configs/admin_overrides_clutch.cfg"

if [[ ! -f "${SP_SRC}" ]]; then
  echo "Missing ${SP_SRC} — git pull em ~/api-csgo" >&2
  exit 1
fi

if [[ -d "${REPO_ROOT}/.git" ]]; then
  LOCAL_HEAD="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || true)"
  if [[ -n "${LOCAL_HEAD}" ]]; then
    echo "Repo at ${LOCAL_HEAD} — run: cd ~/api-csgo && git pull"
  fi
fi

if [[ ! -d "${SM}/scripting" ]]; then
  echo "SourceMod not found at ${SM}" >&2
  exit 1
fi

echo ">>> PTaH (required for z_clutch_skins_bridge compile)"
bash "${REPO_ROOT}/scripts/install-ptah.sh"

echo ">>> kgns weapons.smx (shared SQLite skin DB with ranked)"
bash "${REPO_ROOT}/scripts/install-kgns-weapons.sh"

SPCOMP="${SM}/scripting/spcomp"
if [[ ! -x "${SPCOMP}" ]]; then
  SPCOMP="${SM}/scripting/spcomp64"
fi
if [[ ! -x "${SPCOMP}" ]]; then
  echo "spcomp not found in ${SM}/scripting/" >&2
  exit 1
fi

chmod +x "${SCRIPT_DIR}/install-clutch-skins-bridge.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/verify-clutch-skins-bridge.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/diagnose-steam-and-skins.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/sync-weapons-cfg-from-site.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/ensure-clutch-server-branding.sh" 2>/dev/null || true

echo "Copying source..."
cp -f "${SP_SRC}" "${SM}/scripting/clutch_skins_bridge.sp"
INC_SRC="${REPO_ROOT}/sourcemod/include/weapons.inc"
GLOVES_INC_SRC="${REPO_ROOT}/sourcemod/include/clutch_gloves.inc"
STEAM_INC_SRC="${REPO_ROOT}/sourcemod/include/clutch_steam.inc"
GLOVES_SP_SRC="${REPO_ROOT}/sourcemod/z_clutch_gloves.sp"
GLOVES_CFG_SRC="${REPO_ROOT}/sourcemod/clutch_gloves.cfg"
if [[ -f "${INC_SRC}" ]]; then
  cp -f "${INC_SRC}" "${SM}/scripting/include/weapons.inc"
fi
if [[ -f "${GLOVES_INC_SRC}" ]]; then
  cp -f "${GLOVES_INC_SRC}" "${SM}/scripting/include/clutch_gloves.inc"
fi
if [[ -f "${STEAM_INC_SRC}" ]]; then
  cp -f "${STEAM_INC_SRC}" "${SM}/scripting/include/clutch_steam.inc"
fi
if [[ -f "${GLOVES_SP_SRC}" ]]; then
  cp -f "${GLOVES_SP_SRC}" "${SM}/scripting/z_clutch_gloves.sp"
fi

PLUGIN_SMX="z_clutch_skins_bridge.smx"
GLOVES_SMX="z_clutch_gloves.smx"
LEGACY_SMX="clutch_skins_bridge.smx"

echo "Compiling z_clutch_gloves..."
if [[ -f "${SM}/scripting/z_clutch_gloves.sp" ]]; then
  if ! (cd "${SM}/scripting" && "${SPCOMP}" z_clutch_gloves.sp -o"${SM}/plugins/${GLOVES_SMX}"); then
    echo "Compile failed for z_clutch_gloves.sp" >&2
    rm -f "${SM}/plugins/${GLOVES_SMX}"
    exit 1
  fi
else
  echo "ERROR: missing z_clutch_gloves.sp — git pull" >&2
  exit 1
fi

echo "Compiling z_clutch_skins_bridge..."
if ! (cd "${SM}/scripting" && "${SPCOMP}" clutch_skins_bridge.sp -o"${SM}/plugins/${PLUGIN_SMX}"); then
  echo "Compile failed — fix errors above. Run: cd ~/api-csgo && git pull" >&2
  rm -f "${SM}/plugins/${PLUGIN_SMX}"
  exit 1
fi

if [[ ! -f "${SM}/plugins/${PLUGIN_SMX}" ]]; then
  echo "Compile failed — no .smx output" >&2
  exit 1
fi

# Load after weapons.smx (alphabetical: z_ > weapons)
rm -f "${SM}/plugins/${LEGACY_SMX}"

mkdir -p "${CSGO_ROOT}/cfg/sourcemod"
cp -f "${CFG_SRC}" "${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"
if [[ -f "${GLOVES_CFG_SRC}" ]]; then
  cp -f "${GLOVES_CFG_SRC}" "${CSGO_ROOT}/cfg/sourcemod/clutch_gloves.cfg"
fi

ADMIN_OVERRIDES="${SM}/configs/admin_overrides.cfg"
if [[ -f "${OVERRIDES_SRC}" ]]; then
  MARKER="clutch_inventory_only_ws_admin"
  if [[ -f "${ADMIN_OVERRIDES}" ]] && grep -q "${MARKER}" "${ADMIN_OVERRIDES}"; then
    echo "admin_overrides.cfg already has Clutch !ws restrictions (${MARKER})"
  else
    {
      echo ""
      echo "// ${MARKER} — players use web inventory; admins keep !ws"
      cat "${OVERRIDES_SRC}"
    } >> "${ADMIN_OVERRIDES}"
    echo "Appended !ws admin-only overrides to ${ADMIN_OVERRIDES}"
  fi
fi
GLOVES_CFG_DEPLOY="${CSGO_ROOT}/cfg/sourcemod/clutch_gloves.cfg"
if [[ -f "${GLOVES_CFG_DEPLOY}" ]]; then
  if grep -q 'clutch_gloves_force_body' "${GLOVES_CFG_DEPLOY}"; then
    sed -i 's|^clutch_gloves_force_body.*|clutch_gloves_force_body "1"|g' "${GLOVES_CFG_DEPLOY}"
  else
    printf '\nclutch_gloves_force_body "1"\n' >> "${GLOVES_CFG_DEPLOY}"
  fi
fi

# Fix legacy doubled path in existing cfg (addons/sourcemod/data → data)
CFG_DEPLOY="${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"
if [[ -f "${CFG_DEPLOY}" ]]; then
  sed -i 's|clutch_skins_file "addons/sourcemod/data/clutch_skins.txt"|clutch_skins_file "data/clutch_skins.txt"|g' "${CFG_DEPLOY}"
  if grep -q 'clutch_skins_refresh' "${CFG_DEPLOY}"; then
    sed -i 's|^clutch_skins_refresh.*|clutch_skins_refresh "0"|g' "${CFG_DEPLOY}"
  else
    printf '\nclutch_skins_refresh "0"\n' >> "${CFG_DEPLOY}"
  fi
  if grep -q 'clutch_skins_gloves_world_model' "${CFG_DEPLOY}"; then
    sed -i 's|^clutch_skins_gloves_world_model.*|clutch_skins_gloves_world_model "0"|g' "${CFG_DEPLOY}"
  else
    printf '\nclutch_skins_gloves_world_model "0"\n' >> "${CFG_DEPLOY}"
  fi
fi

DATA_FILE="${SM}/data/clutch_skins.txt"
if [[ -f "${DATA_FILE}" ]]; then
  echo "Note: clutch_skins.txt exists but v3 plugin ignores it (uses weapons DB only)."
fi

CORE_CFG="${SM}/configs/core.cfg"
if [[ -f "${CORE_CFG}" ]]; then
  if grep -q 'FollowCSGOServerGuidelines' "${CORE_CFG}"; then
    if grep -q '"FollowCSGOServerGuidelines"[[:space:]]*"no"' "${CORE_CFG}"; then
      echo "core.cfg OK (FollowCSGOServerGuidelines = no)"
    else
      echo "WARNING: ${CORE_CFG} has FollowCSGOServerGuidelines but not \"no\"."
      echo "  Edit it to: \"FollowCSGOServerGuidelines\" \"no\""
      echo "  Then restart srcds completely."
    fi
  else
    echo "Adding FollowCSGOServerGuidelines to ${CORE_CFG} ..."
    printf '\n"FollowCSGOServerGuidelines" "no"\n' >> "${CORE_CFG}"
    echo "  Added — restart srcds completely for skins to apply."
  fi
else
  echo "WARNING: ${CORE_CFG} not found."
  echo "  Create it or install SourceMod configs, then set:"
  echo "  \"FollowCSGOServerGuidelines\" \"no\""
fi

WEAPONS_SP="${SM}/scripting/weapons.sp"
if [[ -f "${WEAPONS_SP}" ]]; then
  echo ""
  echo "Patching weapons.smx (ReloadClientData + RefreshWeapon natives)..."
  CSGO_ROOT="${CSGO_ROOT}" bash "${REPO_ROOT}/scripts/patch-weapons-reload-native.sh" || {
    echo "WARNING: patch-weapons-reload-native.sh failed — run it manually then: sm plugins reload weapons" >&2
  }
  echo "After install, in screen run: sm plugins reload weapons  (not before — patched smx is built here)"
else
  echo "NOTE: ${WEAPONS_SP} not found — skip weapons native patch (knife colors may not update from site DB)."
fi

echo ""
echo "OK — ${GLOVES_SMX} + ${PLUGIN_SMX} installed (gloves before skins bridge)."
echo "Expected bridge version: $(grep -E '#define PLUGIN_VERSION' "${SP_SRC}" | sed 's/.*"\(.*\)".*/\1/')"
echo "Expected gloves version: $(grep -E '#define PLUGIN_VERSION' "${GLOVES_SP_SRC}" | sed 's/.*"\(.*\)".*/\1/')"
echo ""
echo "Installed to: ${SM}/plugins/${GLOVES_SMX} and ${SM}/plugins/${PLUGIN_SMX}"
ls -la "${SM}/plugins/${GLOVES_SMX}" "${SM}/plugins/${PLUGIN_SMX}"
if command -v md5sum >/dev/null 2>&1; then
  md5sum "${SM}/plugins/${PLUGIN_SMX}"
elif command -v md5 >/dev/null 2>&1; then
  md5 -q "${SM}/plugins/${PLUGIN_SMX}"
fi

LIVE_ROOT="$(detect_live_csgo_root || true)"
if [[ -n "${LIVE_ROOT}" ]]; then
  LIVE_SM="${LIVE_ROOT}/addons/sourcemod"
  echo ""
  echo "Running srcds game dir: ${LIVE_ROOT}"
  if [[ "${LIVE_ROOT}" != "${CSGO_ROOT}" ]]; then
    echo "ERROR: installed to ${CSGO_ROOT} but srcds uses ${LIVE_ROOT}" >&2
    echo "  Re-run: CSGO_ROOT=${LIVE_ROOT} bash scripts/install-clutch-skins-bridge.sh" >&2
    exit 1
  elif [[ -f "${LIVE_SM}/plugins/${PLUGIN_SMX}" ]]; then
    if command -v md5sum >/dev/null 2>&1; then
      echo "Live plugins dir hash:"
      md5sum "${LIVE_SM}/plugins/${GLOVES_SMX}" "${LIVE_SM}/plugins/${PLUGIN_SMX}"
    fi
  fi
else
  echo "TIP: srcds not running — could not auto-detect live game directory."
fi

KGNS_GLOVES_SMX="${SM}/plugins/gloves.smx"
GLOVES_DISABLED_DIR="${SM}/plugins/disabled"
mkdir -p "${GLOVES_DISABLED_DIR}"
if [[ -f "${KGNS_GLOVES_SMX}" ]]; then
  mv -f "${KGNS_GLOVES_SMX}" "${GLOVES_DISABLED_DIR}/gloves.smx"
  echo "Disabled kgns gloves.smx → plugins/disabled/gloves.smx (avoids double gloves)."
elif [[ -f "${GLOVES_DISABLED_DIR}/gloves.smx" ]]; then
  echo "kgns gloves.smx already in plugins/disabled/."
else
  echo "kgns gloves.smx not found — using z_clutch_gloves.smx from this repo."
fi
# Legacy mistaken rename (still loaded as .smx in plugins/)
LEGACY_DISABLED="${SM}/plugins/z_disabled_kgns_gloves.smx"
if [[ -f "${LEGACY_DISABLED}" ]]; then
  mv -f "${LEGACY_DISABLED}" "${GLOVES_DISABLED_DIR}/gloves.smx"
  echo "Moved legacy z_disabled_kgns_gloves.smx into plugins/disabled/."
fi

WEAPONS_SMX="${SM}/plugins/weapons.smx"
if [[ -f "${WEAPONS_SMX}" ]]; then
  echo "weapons.smx found — required for knife models (!ws / PTaH)."
else
  echo "WARNING: weapons.smx missing — knife models will not change."
fi
echo ""
echo "Full deploy (pull + api + plugin + reload): ./scripts/deploy-vps.sh"
echo "Recarregar no CS:"
echo "  ./scripts/reload-clutch-skins-ingame.sh"
echo ""
echo "Ou manualmente (dentro de screen -r) — um comando por linha:"
echo "In-game load order (screen -r) — gloves BEFORE bridge:"
echo "  sm plugins unload z_clutch_skins_bridge"
echo "  sm plugins load z_clutch_gloves"
echo "  sm plugins load z_clutch_skins_bridge"
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
echo ""
echo "Diagnóstico: ./scripts/verify-clutch-skins-bridge.sh"
