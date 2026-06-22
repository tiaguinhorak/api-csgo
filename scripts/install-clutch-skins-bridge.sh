#!/usr/bin/env bash
set -euo pipefail

# Instala e compila clutch_skins_bridge na VPS (rode como csgo na máquina do CS).
#
# Uso:
#   cd ~/api-csgo && git pull
#   ./scripts/install-clutch-skins-bridge.sh
#   (ou: bash scripts/install-clutch-skins-bridge.sh)

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SP_SRC="${REPO_ROOT}/sourcemod/clutch_skins_bridge.sp"
CFG_SRC="${REPO_ROOT}/sourcemod/clutch_skins_bridge.cfg"

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

echo "Copying source..."
cp -f "${SP_SRC}" "${SM}/scripting/clutch_skins_bridge.sp"
INC_SRC="${REPO_ROOT}/sourcemod/include/weapons.inc"
if [[ -f "${INC_SRC}" ]]; then
  cp -f "${INC_SRC}" "${SM}/scripting/include/weapons.inc"
fi

PLUGIN_SMX="z_clutch_skins_bridge.smx"
LEGACY_SMX="clutch_skins_bridge.smx"

echo "Compiling..."
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

mkdir -p "${CSGO_ROOT}/cfg/sourcemod"
cp -f "${CFG_SRC}" "${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"

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
  echo "Patching weapons.smx (Weapons_ReloadClientData native)..."
  CSGO_ROOT="${CSGO_ROOT}" bash "${REPO_ROOT}/scripts/patch-weapons-reload-native.sh" || {
    echo "WARNING: patch-weapons-reload-native.sh failed — colors may not sync until you run it manually." >&2
  }
else
  echo "NOTE: ${WEAPONS_SP} not found — skip weapons native patch (knife colors may not update from site DB)."
fi

echo ""
echo "OK — ${PLUGIN_SMX} installed (loads after weapons.smx)."
echo "Expected plugin version: $(grep -E '#define PLUGIN_VERSION' "${SP_SRC}" | sed 's/.*"\(.*\)".*/\1/')"
echo ""
echo "Installed to: ${SM}/plugins/${PLUGIN_SMX}"
ls -la "${SM}/plugins/${PLUGIN_SMX}"
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
    echo "WARNING: plugin installed to ${CSGO_ROOT} but srcds uses ${LIVE_ROOT}"
    echo "  Re-run: CSGO_ROOT=${LIVE_ROOT} bash scripts/install-clutch-skins-bridge.sh"
  elif [[ -f "${LIVE_SM}/plugins/${PLUGIN_SMX}" ]]; then
    if command -v md5sum >/dev/null 2>&1; then
      echo "Live plugins dir hash:"
      md5sum "${LIVE_SM}/plugins/${PLUGIN_SMX}"
    fi
  fi
else
  echo "TIP: srcds not running — could not auto-detect live game directory."
fi

GLOVES_SMX="${SM}/plugins/gloves.smx"
GLOVES_DISABLED_DIR="${SM}/plugins/disabled"
mkdir -p "${GLOVES_DISABLED_DIR}"
if [[ -f "${GLOVES_SMX}" ]]; then
  mv -f "${GLOVES_SMX}" "${GLOVES_DISABLED_DIR}/gloves.smx"
  echo "Disabled kgns gloves.smx → plugins/disabled/gloves.smx (avoids double gloves; bridge applies from site DB)."
elif [[ -f "${GLOVES_DISABLED_DIR}/gloves.smx" ]]; then
  echo "kgns gloves.smx already in plugins/disabled/."
else
  echo "kgns gloves.smx not found — bridge applies gloves from SQLite only."
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
echo "  sm plugins unload z_clutch_skins_bridge"
echo "  sm plugins load z_clutch_skins_bridge"
echo "  sm plugins info z_clutch_skins_bridge"
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
echo ""
echo "Diagnóstico: ./scripts/verify-clutch-skins-bridge.sh"
