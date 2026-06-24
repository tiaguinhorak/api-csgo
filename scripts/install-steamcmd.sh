#!/usr/bin/env bash
# Instala SteamCMD (Valve) se ainda não existir.
# Uso: bash scripts/install-steamcmd.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

STEAMCMD_DIR="${STEAMCMD_DIR:-${HOME}/steamcmd}"
STEAMCMD="${STEAMCMD:-${STEAMCMD_DIR}/steamcmd.sh}"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

if [[ -x "${STEAMCMD}" ]]; then
  echo "OK: SteamCMD já instalado em ${STEAMCMD}"
  exit 0
fi

echo ">>> Instalando SteamCMD em ${STEAMCMD_DIR}"
mkdir -p "${STEAMCMD_DIR}"
cd "${STEAMCMD_DIR}"

if [[ ! -f steamcmd_linux.tar.gz ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${STEAMCMD_URL}" -o steamcmd_linux.tar.gz
  elif command -v wget >/dev/null 2>&1; then
    wget -qO steamcmd_linux.tar.gz "${STEAMCMD_URL}"
  else
    echo "ERROR: curl ou wget necessário para baixar SteamCMD" >&2
    exit 1
  fi
fi

tar -xzf steamcmd_linux.tar.gz
chmod +x "${STEAMCMD_DIR}/steamcmd.sh" 2>/dev/null || true

echo ">>> Primeira execução SteamCMD (auto-update)"
"${STEAMCMD_DIR}/steamcmd.sh" +quit || true

if [[ ! -x "${STEAMCMD}" ]]; then
  echo "ERROR: steamcmd.sh não ficou executável em ${STEAMCMD}" >&2
  exit 1
fi

echo "OK: SteamCMD em ${STEAMCMD}"
