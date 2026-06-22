#!/usr/bin/env bash
set -euo pipefail

# Dev: site local (npm run dev) + CS na VPS.
# 1) Baixa export do Next.js local
# 2) Envia clutch_skins.txt para a VPS via SCP
#
# Env:
#   CLUTCH_SITE_URL     — default http://127.0.0.1:3000
#   CSGO_SKINS_SYNC_KEY — igual ao site/.env
#   CLUTCH_SSH_TARGET   — default csgo@188.220.168.233
#   CLUTCH_SSH_REMOTE   — path no servidor CS:GO
#   CLUTCH_SSH_KEY      — opcional (-i para ssh/scp)

SITE_URL="${CLUTCH_SITE_URL:-http://127.0.0.1:3000}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
SSH_TARGET="${CLUTCH_SSH_TARGET:-csgo@188.220.168.233}"
REMOTE_PATH="${CLUTCH_SSH_REMOTE:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"
SSH_KEY="${CLUTCH_SSH_KEY:-}"

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

echo "Fetching ${SITE_URL}/api/csgo/skins/export ..."
curl -fsS \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  "${SITE_URL}/api/csgo/skins/export" \
  -o "${LOCAL_TMP}"

if [[ ! -s "${LOCAL_TMP}" ]]; then
  echo "Export empty — equip a skin on the local site first." >&2
  rm -f "${LOCAL_TMP}"
  exit 1
fi

echo "Uploading to ${SSH_TARGET}:${REMOTE_PATH} ..."
scp "${SCP_OPTS[@]}" "${LOCAL_TMP}" "${SSH_TARGET}:${REMOTE_PATH}.tmp"
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "mv -f '${REMOTE_PATH}.tmp' '${REMOTE_PATH}' && chmod 644 '${REMOTE_PATH}'"

rm -f "${LOCAL_TMP}"
echo "OK — synced. On server: sm_reloadclutchskins"
