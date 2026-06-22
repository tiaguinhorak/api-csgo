#!/usr/bin/env bash
set -euo pipefail

# Instala e compila clutch_skins_bridge na VPS (rode como csgo na máquina do CS).
#
# Uso:
#   cd ~/api-csgo/scripts
#   chmod +x install-clutch-skins-bridge.sh
#   ./install-clutch-skins-bridge.sh

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

echo ""
echo "OK — ${PLUGIN_SMX} installed (loads after weapons.smx)."
echo "Expected plugin version: $(grep -E '#define PLUGIN_VERSION' "${SP_SRC}" | sed 's/.*"\(.*\)".*/\1/')"

GLOVES_SMX="${SM}/plugins/gloves.smx"
if [[ -f "${GLOVES_SMX}" ]]; then
  echo "gloves.smx found — same SQLite DB for glove menu + bridge apply."
else
  echo "NOTE: gloves.smx not found — bridge still applies gloves from DB; install kgns Gloves for !gloves menu."
fi

WEAPONS_SMX="${SM}/plugins/weapons.smx"
if [[ -f "${WEAPONS_SMX}" ]]; then
  echo "weapons.smx found — required for knife models (!ws / PTaH)."
else
  echo "WARNING: weapons.smx missing — knife models will not change."
fi
echo ""
echo "Full deploy (api + plugin): ./scripts/deploy-skins-v3.sh"
echo "Recarregar no CS:"
echo "  ./scripts/reload-clutch-skins-ingame.sh"
echo ""
echo "Ou manualmente (dentro de screen -r):"
echo "  sm plugins reload z_clutch_skins_bridge"
echo "  sm plugins info z_clutch_skins_bridge"
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
echo ""
echo "Diagnóstico: ./scripts/verify-clutch-skins-bridge.sh"
