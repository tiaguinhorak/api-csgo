#!/usr/bin/env bash
# Garante bin/srcds_linux para ./srcds_run (alguns installs Steam colocam o binário na raiz).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
BIN_DIR="${SERVER_ROOT}/bin"
CANONICAL="${BIN_DIR}/srcds_linux"
ROOT_BIN="${SERVER_ROOT}/srcds_linux"

is_elf_binary() {
  local path="$1"
  [[ -f "${path}" ]] && command -v file >/dev/null 2>&1 && file -b "${path}" | grep -qi 'ELF'
}

if [[ -f "${CANONICAL}" ]]; then
  echo "OK: ${CANONICAL} exists"
  exit 0
fi

if is_elf_binary "${ROOT_BIN}"; then
  mkdir -p "${BIN_DIR}"
  ln -sf ../srcds_linux "${CANONICAL}"
  echo "OK: linked ${CANONICAL} → ../srcds_linux"
  exit 0
fi

if [[ -f "${SERVER_ROOT}/game/bin/linuxsteamrt64/cs2" ]] \
  || [[ -f "${SERVER_ROOT}/game/csgo/bin/linuxsteamrt64/cs2" ]]; then
  echo "ERROR: install parece CS2 — ./srcds_run -game csgo não funciona." >&2
  echo "       Use cs2.sh ou reinstale CS:GO legacy (app 740, platform linux)." >&2
  exit 1
fi

echo "ERROR: srcds_linux não encontrado em bin/ nem na raiz do server." >&2
echo "       Rode: steamcmd +force_install_dir ${SERVER_ROOT} +app_update 740 validate" >&2
if [[ -f "${ROOT_BIN}" ]]; then
  echo "       ${ROOT_BIN} existe mas não é ELF: $(file -b "${ROOT_BIN}" 2>/dev/null || echo '?')"
fi
exit 1
