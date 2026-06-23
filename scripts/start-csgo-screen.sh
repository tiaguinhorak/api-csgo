#!/usr/bin/env bash
# Start CS:GO srcds in screen (logs boot output if it crashes).
#
# Uso na VPS:
#   cd ~/api-csgo && bash scripts/start-csgo-screen.sh
#
# Env (.env): CSGO_SERVER_DIR, CSGO_RCON_PASSWORD, CSGO_GSLT_TOKEN, CLUTCH_CS_SCREEN
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
SCREEN_NAME="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"
PORT="${CSGO_RCON_PORT:-27015}"
RCON="${CSGO_RCON_PASSWORD:-clutchclube}"
GSLT="${CSGO_GSLT_TOKEN:-}"
MAP="${CSGO_START_MAP:-de_dust2}"
MAXPLAYERS="${CSGO_MAXPLAYERS:-10}"
GAME_TYPE="${CSGO_GAME_TYPE:-0}"
GAME_MODE="${CSGO_GAME_MODE:-1}"
BOOT_LOG="${SERVER_ROOT}/csgo/clutch-srcds-boot.log"

if [[ ! -x "${SERVER_ROOT}/srcds_run" ]]; then
  echo "ERROR: ${SERVER_ROOT}/srcds_run not found or not executable" >&2
  echo "Run: bash scripts/diagnose-csgo-srcds.sh" >&2
  exit 1
fi

echo "[start-csgo] Stopping old screen / srcds..."
screen -S "${SCREEN_NAME}" -X quit 2>/dev/null || true
fuser -k "${PORT}/udp" 2>/dev/null || true
pkill -u "$(id -u)" -f srcds_linux 2>/dev/null || true
sleep 2

mkdir -p "${SERVER_ROOT}/csgo"
echo "===== boot $(date -Is) =====" >> "${BOOT_LOG}"

RUNLINE="cd '${SERVER_ROOT}' && ./srcds_run -tickrate 128 -game csgo -console -usercon -port ${PORT} +game_type ${GAME_TYPE} +game_mode ${GAME_MODE} +map ${MAP} +rcon_password '${RCON}' -maxplayers ${MAXPLAYERS}"
if [[ -n "${GSLT}" ]]; then
  RUNLINE+=" +sv_setsteamaccount '${GSLT}'"
else
  echo "[start-csgo] WARN: CSGO_GSLT_TOKEN not set in .env — LAN-only or may fail to list on Steam" >&2
fi
RUNLINE+=" 2>&1 | tee -a '${BOOT_LOG}'"

echo "[start-csgo] screen -dmS ${SCREEN_NAME}"
screen -dmS "${SCREEN_NAME}" bash -lc "${RUNLINE}"

sleep 4

if screen -ls 2>/dev/null | grep -qF ".${SCREEN_NAME}"; then
  echo "[start-csgo] screen session OK"
  screen -ls | grep -F "${SCREEN_NAME}" || true
else
  echo "[start-csgo] ERROR: screen died — srcds probably crashed. Log:" >&2
  tail -30 "${BOOT_LOG}" >&2
  exit 1
fi

if pgrep -u "$(id -u)" -f srcds_linux >/dev/null 2>&1; then
  echo "[start-csgo] srcds_linux running"
  pgrep -u "$(id -u)" -af srcds_linux
else
  echo "[start-csgo] WARN: no srcds_linux yet — wait or check log:" >&2
  tail -20 "${BOOT_LOG}" >&2
fi

echo ""
echo "Attach: screen -r ${SCREEN_NAME}"
echo "Reload plugin: cd ~/api-csgo && bash scripts/reload-clutch-skins-ingame.sh"
