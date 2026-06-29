#!/usr/bin/env bash
set -euo pipefail

# Validate CS:GO dedicated server game files (app 740).
# Agent models (custom_player) are NOT in app 740 — run install-agent-models.sh after this.
#
# Usage (stop srcds first):
#   ./scripts/validate-csgo-game-files.sh
#
# Same as scripts/update-csgo-server.sh but also runs verify-agent-models.sh.

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CSGO_INSTALL="${CSGO_INSTALL:-$(dirname "${CSGO_ROOT}")}"
STEAMCMD="${STEAMCMD:-/home/csgo/steamcmd/steamcmd.sh}"

if [[ ! -x "${STEAMCMD}" ]]; then
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

if [[ ! -x "${STEAMCMD}" ]]; then
  echo "steamcmd not found at ${STEAMCMD}"
  echo "Install: https://developer.valvesoftware.com/wiki/SteamCMD"
  exit 1
fi

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "WARN: srcds_linux is running — stop the server before validate (files may not update)."
  echo "  screen -r  → stop server, or: bash scripts/start-csgo-screen.sh after update"
fi

echo "SteamCMD:   ${STEAMCMD}"
echo "Install dir: ${CSGO_INSTALL}  (must contain csgo/ and steamapps/)"
echo "CSGO game:   ${CSGO_ROOT}"
echo ""

if [[ ! -d "${CSGO_INSTALL}/csgo" ]]; then
  echo "ERROR: ${CSGO_INSTALL}/csgo not found — CSGO_INSTALL should be parent of csgo/, e.g. /home/csgo/server"
  exit 1
fi

echo "Running app_update 740 validate (may take several minutes)..."
set +e
"${STEAMCMD}" \
  +force_install_dir "${CSGO_INSTALL}" \
  +login anonymous \
  +app_update 740 validate \
  +quit
STEAM_EXIT=$?
set -e

if [[ "${STEAM_EXIT}" -ne 0 ]]; then
  echo ""
  echo "SteamCMD exited with code ${STEAM_EXIT} (0x202 = wrong install dir or server running)."
  echo "Try:"
  echo "  1) Stop srcds, then re-run this script"
  echo "  2) CSGO_INSTALL=${CSGO_INSTALL} STEAMCMD=${STEAMCMD} bash scripts/update-csgo-server.sh"
  echo "  3) Agent models: ./scripts/install-agent-models.sh"
  echo "     (app 740 does not ship models/player/custom_player)"
fi

echo ""
echo "Checking agent models (requires install-agent-models.sh if MISSING)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/verify-agent-models.sh" || true
