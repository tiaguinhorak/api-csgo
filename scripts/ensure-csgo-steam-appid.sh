#!/usr/bin/env bash
# Garante steam_appid.txt (730) — necessário para auth Steam ao conectar clientes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
APPID_FILE="${SERVER_ROOT}/csgo/steam_appid.txt"
APPID="730"

mkdir -p "${SERVER_ROOT}/csgo"
if [[ -f "${APPID_FILE}" ]] && grep -qx "${APPID}" "${APPID_FILE}"; then
  echo "OK: ${APPID_FILE} = ${APPID}"
else
  printf '%s\n' "${APPID}" > "${APPID_FILE}"
  echo "Wrote ${APPID_FILE} = ${APPID}"
fi
