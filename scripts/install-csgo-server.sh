#!/usr/bin/env bash
# Baixa/atualiza CS:GO Legacy dedicado (Steam app 740) via SteamCMD.
# Uso: bash scripts/install-csgo-server.sh
#      CSGO_FORCE_VALIDATE=1 bash scripts/install-csgo-server.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

CSGO_INSTALL="${CSGO_SERVER_DIR:-${HOME}/server}"
STEAMCMD_DIR="${STEAMCMD_DIR:-${HOME}/steamcmd}"
STEAMCMD="${STEAMCMD:-${STEAMCMD_DIR}/steamcmd.sh}"
FORCE="${CSGO_FORCE_VALIDATE:-0}"

if [[ ! -x "${STEAMCMD}" ]]; then
  echo ">>> SteamCMD ausente — instalando..."
  bash "${REPO_ROOT}/scripts/install-steamcmd.sh"
fi

if [[ -x "${CSGO_INSTALL}/srcds_run" && "${FORCE}" != "1" ]]; then
  echo "OK: CS:GO já em ${CSGO_INSTALL} (srcds_run existe)"
  exit 0
fi

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "ERROR: srcds_linux rodando — pare antes de instalar/atualizar:" >&2
  echo "  bash scripts/start-csgo-screen.sh  (reinicia após update)" >&2
  exit 1
fi

mkdir -p "${CSGO_INSTALL}"

echo ">>> Baixando CS:GO (app 740) em ${CSGO_INSTALL}"
echo "    (pode levar vários minutos na primeira vez)"

run_update() {
  "${STEAMCMD}" \
    +force_install_dir "${CSGO_INSTALL}" \
    +login anonymous \
    +app_update 740 validate \
    +quit
}

if ! run_update; then
  echo "WARN: primeira tentativa falhou — SteamCMD costuma precisar de 2ª execução"
  sleep 3
  run_update
fi

if [[ ! -x "${CSGO_INSTALL}/srcds_run" ]]; then
  echo "ERROR: srcds_run não encontrado após app_update 740" >&2
  echo "Verifique: ls -la ${CSGO_INSTALL}" >&2
  exit 1
fi

bash "${REPO_ROOT}/scripts/ensure-csgo-srcds-layout.sh" || true

echo "OK: CS:GO instalado em ${CSGO_INSTALL}"
