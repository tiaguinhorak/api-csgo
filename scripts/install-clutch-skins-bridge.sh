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
chmod +x "${SCRIPT_DIR}/reload-clutch-skins-ingame.sh" 2>/dev/null || true

echo "Copying source..."
cp -f "${SP_SRC}" "${SM}/scripting/clutch_skins_bridge.sp"

echo "Compiling..."
(cd "${SM}/scripting" && "${SPCOMP}" clutch_skins_bridge.sp -o"${SM}/plugins/clutch_skins_bridge.smx")

if [[ ! -f "${SM}/plugins/clutch_skins_bridge.smx" ]]; then
  echo "Compile failed — no .smx output" >&2
  exit 1
fi

mkdir -p "${CSGO_ROOT}/cfg/sourcemod"
cp -f "${CFG_SRC}" "${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"

# Fix legacy doubled path in existing cfg (addons/sourcemod/data → data)
CFG_DEPLOY="${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"
if [[ -f "${CFG_DEPLOY}" ]]; then
  sed -i 's|clutch_skins_file "addons/sourcemod/data/clutch_skins.txt"|clutch_skins_file "data/clutch_skins.txt"|g' "${CFG_DEPLOY}"
fi

DATA_FILE="${SM}/data/clutch_skins.txt"
if [[ ! -f "${DATA_FILE}" ]]; then
  echo "Warning: ${DATA_FILE} missing — upload via WinSCP or run sync-clutch-skins.sh"
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
echo "OK — clutch_skins_bridge.smx installed."
echo ""
echo "Recarregar no CS sem colar logs no console:"
echo "  ./scripts/reload-clutch-skins-ingame.sh"
echo ""
echo "Ou manualmente (UM comando por linha, dentro de screen -r):"
echo "  sm plugins reload clutch_skins_bridge"
echo "  sm plugins info clutch_skins_bridge"
echo "  clutch_skins_file \"${REMOTE_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}\""
echo "  clutch_skins_debug 1"
echo "  sm_reloadclutchskins"
echo "  sm_clutch_applyskins"
echo ""
echo "Diagnóstico: ./scripts/verify-clutch-skins-bridge.sh"
