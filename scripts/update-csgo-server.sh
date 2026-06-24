#!/usr/bin/env bash
set -euo pipefail

# Update CS:GO dedicated server via SteamCMD (fixes MasterRequestRestart / stale item schema).
#
# Usage (as csgo, with srcds stopped):
#   bash scripts/update-csgo-server.sh

CSGO_INSTALL="${CSGO_INSTALL:-/home/csgo/server}"
STEAMCMD="${STEAMCMD:-/home/csgo/steamcmd/steamcmd.sh}"

if [[ ! -x "${STEAMCMD}" ]]; then
  echo "ERROR: steamcmd not found at ${STEAMCMD}" >&2
  echo "Install SteamCMD first, then re-run." >&2
  exit 1
fi

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "ERROR: srcds_linux is running — stop the server first:" >&2
  echo "  bash scripts/start-csgo-screen.sh  (restarts after update)" >&2
  exit 1
fi

echo ">>> Updating CS:GO in ${CSGO_INSTALL}"
"${STEAMCMD}" \
  +force_install_dir "${CSGO_INSTALL}" \
  +login anonymous \
  +app_update 740 validate \
  +quit

echo "OK — CS:GO updated. Start server: bash scripts/start-csgo-screen.sh"
