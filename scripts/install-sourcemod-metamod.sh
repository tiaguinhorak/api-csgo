#!/usr/bin/env bash
# Instala MetaMod:Source + SourceMod no CS:GO dedicado (Linux).
# Uso: bash scripts/install-sourcemod-metamod.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
CSGO_ROOT="${SERVER_ROOT}/csgo"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ ! -d "${CSGO_ROOT}" ]]; then
  echo "ERROR: ${CSGO_ROOT} não existe — instale o CS:GO (app 740) primeiro." >&2
  exit 1
fi

MMS_URL="https://mms.alliedmods.net/mmsdrop/1.12/mmsource-1.12.0-git1224-linux.tar.gz"
SM_URL="https://www.sourcemod.net/smdrop/1.12/sourcemod-1.12.0-git7239-linux.tar.gz"

echo ">>> MetaMod:Source"
wget -qO "${TMP_DIR}/mms.tar.gz" "${MMS_URL}"
tar -xzf "${TMP_DIR}/mms.tar.gz" -C "${CSGO_ROOT}"

echo ">>> SourceMod"
wget -qO "${TMP_DIR}/sm.tar.gz" "${SM_URL}"
tar -xzf "${TMP_DIR}/sm.tar.gz" -C "${CSGO_ROOT}"

if [[ ! -x "${CSGO_ROOT}/addons/sourcemod/scripting/spcomp" ]] \
  && [[ ! -x "${CSGO_ROOT}/addons/sourcemod/scripting/spcomp64" ]]; then
  echo "ERROR: SourceMod incompleto em ${CSGO_ROOT}/addons/sourcemod" >&2
  exit 1
fi

echo ""
echo "OK: MetaMod + SourceMod em ${CSGO_ROOT}/addons/"
echo "Verifique:"
echo "  ls ${CSGO_ROOT}/addons/metamod"
echo "  ls ${CSGO_ROOT}/addons/sourcemod/scripting/spcomp*"
