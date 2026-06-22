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

DATA_FILE="${SM}/data/clutch_skins.txt"
if [[ ! -f "${DATA_FILE}" ]]; then
  echo "Warning: ${DATA_FILE} missing — upload via WinSCP or run sync-clutch-skins.sh"
fi

echo ""
echo "OK — clutch_skins_bridge.smx installed."
echo ""
echo "No console do CS (RCON/admin) ou SSH:"
echo "  sm plugins reload"
echo "  sm plugins list | grep clutch"
echo ""
echo "Comando admin (precisa flag root no SourceMod):"
echo "  sm_reloadclutchskins"
echo ""
echo "Ou aguarde ~30s (clutch_skins_refresh) e respawn."
echo ""
echo "Se skins não aparecem, confira core.cfg:"
echo "  \"FollowCSGOServerGuidelines\" \"no\""
echo "  (restart completo do srcds após mudar)"
