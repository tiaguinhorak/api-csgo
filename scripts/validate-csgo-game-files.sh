#!/usr/bin/env bash
set -euo pipefail

# Validate CS:GO dedicated server game files (includes agent models in custom_player).
#
# Usage:
#   ./scripts/validate-csgo-game-files.sh
#
# Requires steamcmd installed — common paths:
#   ~/steamcmd/steamcmd.sh
#   /home/steam/steamcmd/steamcmd.sh

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
STEAMCMD="${STEAMCMD:-}"

if [[ -z "${STEAMCMD}" ]]; then
  for candidate in \
    "${HOME}/steamcmd/steamcmd.sh" \
    "/home/steam/steamcmd/steamcmd.sh" \
    "/usr/games/steamcmd" \
    "/usr/local/bin/steamcmd"; do
    if [[ -x "${candidate}" ]]; then
      STEAMCMD="${candidate}"
      break
    fi
  done
fi

if [[ -z "${STEAMCMD}" || ! -x "${STEAMCMD}" ]]; then
  echo "steamcmd not found."
  echo "Install: https://developer.valvesoftware.com/wiki/SteamCMD"
  echo "Then run:"
  echo "  STEAMCMD=/path/to/steamcmd.sh ./scripts/validate-csgo-game-files.sh"
  exit 1
fi

APP_DIR="$(dirname "$(dirname "${CSGO_ROOT}")")"
echo "SteamCMD: ${STEAMCMD}"
echo "App dir:  ${APP_DIR}"
echo "CSGO:     ${CSGO_ROOT}"
echo ""
echo "Running app_update 740 validate (may take several minutes)..."

"${STEAMCMD}" +force_install_dir "${APP_DIR}" +login anonymous \
  +app_update 740 validate +quit

echo ""
echo "Done. Checking agent models..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/verify-agent-models.sh"
