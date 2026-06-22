#!/usr/bin/env bash
set -euo pipefail

# Envia comandos ao console do srcds via screen (evita colar logs no CS por engano).
#
# Uso na VPS:
#   ./scripts/reload-clutch-skins-ingame.sh
#
# Env:
#   CLUTCH_CS_SCREEN — default csgo-clutch-#1

SCREEN_NAME="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"
SKINS_PATH="${CLUTCH_SKINS_OUT:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"

if ! screen -ls | grep -q "[[:space:]]${SCREEN_NAME}[[:space:]]"; then
  echo "Screen session '${SCREEN_NAME}' not found. List: screen -ls" >&2
  exit 1
fi

send_cmd() {
  local cmd="$1"
  echo ">>> ${cmd}"
  screen -S "${SCREEN_NAME}" -p 0 -X stuff "${cmd}^M"
  sleep 0.4
}

send_cmd "sm plugins reload clutch_skins_bridge"
send_cmd "sm plugins info clutch_skins_bridge"
send_cmd "clutch_skins_file \"${SKINS_PATH}\""
send_cmd "clutch_skins_debug 1"
send_cmd "sm_reloadclutchskins"
send_cmd "sm_clutch_applyskins"

echo ""
echo "Done. Check server log above in screen -r for:"
echo "  Clutch Skins Bridge (1.0.8)"
echo "  [Clutch] Applied weapon_bayonet paintkit ..."
echo ""
echo "Then respawn in game (kill)."
