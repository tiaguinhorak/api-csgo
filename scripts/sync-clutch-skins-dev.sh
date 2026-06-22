#!/usr/bin/env bash
set -euo pipefail

# Dev: rode no seu PC (não na VPS do CS).
# Site local (npm run dev) → SCP do export para o servidor de jogo.
#
# Na VPS do CS use: ./sync-clutch-skins.sh (sem SCP).
#
# Env:
#   CLUTCH_SITE_URL     — default http://127.0.0.1:3000 (Next.js no PC)
#   CSGO_SKINS_SYNC_KEY — igual ao site/.env
#   CLUTCH_SSH_TARGET   — default csgo@188.220.168.233
#   CLUTCH_SSH_REMOTE   — path no servidor CS:GO
#   CLUTCH_SSH_KEY      — opcional (-i para ssh/scp)

SITE_URL="${CLUTCH_SITE_URL:-http://127.0.0.1:3000}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
SSH_TARGET="${CLUTCH_SSH_TARGET:-csgo@188.220.168.233}"
REMOTE_PATH="${CLUTCH_SSH_REMOTE:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"
SSH_KEY="${CLUTCH_SSH_KEY:-}"
EXPORT_URL="${SITE_URL%/}/api/csgo/skins/export"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY is required (same as site/.env)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_TMP="${SCRIPT_DIR}/.clutch_skins.tmp"

SSH_OPTS=()
SCP_OPTS=()
if [[ -n "${SSH_KEY}" ]]; then
  SSH_OPTS+=(-i "${SSH_KEY}")
  SCP_OPTS+=(-i "${SSH_KEY}")
fi

echo "Fetching ${EXPORT_URL} ..."
HTTP_CODE="$(curl -sS -o "${LOCAL_TMP}" -w "%{http_code}" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  "${EXPORT_URL}" || echo "000")"

if [[ "${HTTP_CODE}" != "200" ]]; then
  rm -f "${LOCAL_TMP}"
  echo "Export failed (HTTP ${HTTP_CODE})." >&2
  if [[ "${SITE_URL}" == "http://127.0.0.1:3000" ]] || [[ "${SITE_URL}" == "http://localhost:3000" ]]; then
    echo "" >&2
    echo "Este script roda no seu PC com npm run dev (Next.js na porta 3000)." >&2
    echo "Na VPS do CS, 127.0.0.1:3000 é outro serviço (api-csgo) — use:" >&2
    echo "  CSGO_SKINS_SYNC_KEY=... CLUTCH_SITE_URL=https://seu-site ./sync-clutch-skins.sh" >&2
  else
    echo "Confira: site deployado com /api/csgo/skins/export e CSGO_SKINS_SYNC_KEY correto." >&2
  fi
  exit 1
fi

if [[ ! -s "${LOCAL_TMP}" ]]; then
  echo "Export empty — equip a skin on the site first." >&2
  rm -f "${LOCAL_TMP}"
  exit 1
fi

echo "Uploading to ${SSH_TARGET}:${REMOTE_PATH} ..."
scp "${SCP_OPTS[@]}" "${LOCAL_TMP}" "${SSH_TARGET}:${REMOTE_PATH}.tmp"
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "mv -f '${REMOTE_PATH}.tmp' '${REMOTE_PATH}' && chmod 644 '${REMOTE_PATH}'"

rm -f "${LOCAL_TMP}"
echo "OK — synced. On server: sm_reloadclutchskins"
