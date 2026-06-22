#!/usr/bin/env bash
set -euo pipefail

# Recarrega plugin v3 (DB-only) no srcds via screen.
#
# Uso na VPS:
#   ./scripts/reload-clutch-skins-ingame.sh

SCREEN_NAME="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"

if ! screen -ls | grep -qF ".${SCREEN_NAME}"; then
  echo "Screen session matching '*${SCREEN_NAME}' not found. List: screen -ls" >&2
  exit 1
fi

FULL_SCREEN="$(screen -ls | grep -F ".${SCREEN_NAME}" | head -1 | awk '{print $1}')"
if [[ -z "${FULL_SCREEN}" ]]; then
  echo "Could not resolve screen session id" >&2
  exit 1
fi

echo "Using screen session: ${FULL_SCREEN}"

send_cmd() {
  local cmd="$1"
  echo ">>> ${cmd}"
  screen -S "${FULL_SCREEN}" -p 0 -X stuff "${cmd}^M"
  sleep 0.4
}

send_cmd "sm plugins unload clutch_skins_bridge"
send_cmd "sm plugins unload z_clutch_skins_bridge"
send_cmd "sm plugins load z_clutch_skins_bridge"
send_cmd "sm plugins info z_clutch_skins_bridge"
send_cmd "clutch_skins_debug 1"
send_cmd "sm_reloadclutchskins"
send_cmd "sm_clutch_applyskins"

echo ""
echo "Done. Expect plugin Version: 3.2.0"
echo "If still 3.1.0: wrong CSGO_ROOT — run install with CSGO_ROOT from install script output."
echo "Then respawn in game (kill)."
