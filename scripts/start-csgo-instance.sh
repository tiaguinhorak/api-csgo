#!/usr/bin/env bash
# Sobe uma instância ADICIONAL de srcds (não mata outras portas/sessions).
#
# Uso:
#   bash scripts/start-csgo-instance.sh 27016 csgo-ranked-27016 de_dust2
#   PORT=27017 SCREEN=csgo-warmup-27017 MAP=de_mirage bash scripts/start-csgo-instance.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${1:-${PORT:-27016}}"
SCREEN_NAME="${2:-${SCREEN:-csgo-instance-${PORT}}}"
MAP="${3:-${MAP:-de_dust2}}"

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
RCON="${CSGO_RCON_PASSWORD:-clutchclube}"
GSLT="${CSGO_GSLT_TOKEN:-}"
MAXPLAYERS="${CSGO_MAXPLAYERS:-10}"
GAME_TYPE="${CSGO_GAME_TYPE:-0}"
GAME_MODE="${CSGO_GAME_MODE:-1}"
BIND_IP="${CSGO_BIND_IP:-0.0.0.0}"
BOOT_LOG="${SERVER_ROOT}/csgo/clutch-srcds-${PORT}.log"

if [[ ! -x "${SERVER_ROOT}/srcds_run" ]]; then
  echo "ERROR: ${SERVER_ROOT}/srcds_run not found" >&2
  exit 1
fi

echo "[instance] port=${PORT} screen=${SCREEN_NAME} map=${MAP}"

# Mata só esta session/porta — não toca em 27015 ou outras.
screen -S "${SCREEN_NAME}" -X quit 2>/dev/null || true
fuser -k "${PORT}/udp" 2>/dev/null || true
fuser -k "${PORT}/tcp" 2>/dev/null || true
sleep 1

mkdir -p "${SERVER_ROOT}/csgo"
echo "===== boot $(date -Is) port=${PORT} =====" >> "${BOOT_LOG}"

RUNLINE="cd '${SERVER_ROOT}' && ./srcds_run -tickrate 128 -game csgo -console -usercon -ip ${BIND_IP} -port ${PORT} +game_type ${GAME_TYPE} +game_mode ${GAME_MODE} +map ${MAP} +rcon_password '${RCON}' -maxplayers ${MAXPLAYERS}"
if [[ -n "${GSLT}" ]]; then
  RUNLINE+=" +sv_setsteamaccount '${GSLT}'"
else
  echo "[instance] WARN: CSGO_GSLT_TOKEN vazio — pode falhar listagem Steam" >&2
fi
RUNLINE+=" 2>&1 | tee -a '${BOOT_LOG}'"

screen -dmS "${SCREEN_NAME}" bash -lc "${RUNLINE}"
sleep 4

if screen -ls 2>/dev/null | grep -qF ".${SCREEN_NAME}"; then
  echo "[instance] OK — screen ${SCREEN_NAME} rodando"
  echo "Registre no painel: host público + porta ${PORT}, depois Testar conexão."
else
  echo "[instance] ERROR: screen morreu — log:" >&2
  tail -25 "${BOOT_LOG}" >&2
  exit 1
fi
