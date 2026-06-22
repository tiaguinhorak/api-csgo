#!/usr/bin/env bash
set -euo pipefail

# Dev: rode no seu PC (não na VPS do CS).
# Site local (npm run dev) → SCP do export para o servidor de jogo.
#
# Na VPS do CS use: ./sync-clutch-skins.sh (sem SCP).
#
# Env:
#   CLUTCH_SITE_URL       — default http://127.0.0.1:3000 (Next.js no PC)
#   CSGO_SKINS_SYNC_KEY   — igual ao site/.env
#   CLUTCH_SSH_TARGET     — default csgo@188.220.168.233
#   CLUTCH_SSH_REMOTE     — path no servidor CS:GO
#   CLUTCH_SSH_KEY        — chave privada (-i). Não usa/replace suas outras chaves; crie uma nova:
#                           ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_csgo_vps -N ""
#   CLUTCH_FETCH_ONLY=1   — só baixa export (sem SSH). Arquivo: scripts/clutch_skins.export.txt
#   CLUTCH_SSH_PASSWORD   — senha para sshpass (opcional, não recomendado)

SITE_URL="${CLUTCH_SITE_URL:-http://127.0.0.1:3000}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
SSH_TARGET="${CLUTCH_SSH_TARGET:-csgo@188.220.168.233}"
REMOTE_PATH="${CLUTCH_SSH_REMOTE:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"
SSH_KEY="${CLUTCH_SSH_KEY:-}"
FETCH_ONLY="${CLUTCH_FETCH_ONLY:-}"
SSH_PASSWORD="${CLUTCH_SSH_PASSWORD:-}"
EXPORT_URL="${SITE_URL%/}/api/csgo/skins/export"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY is required (same as site/.env)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_TMP="${SCRIPT_DIR}/.clutch_skins.tmp"
LOCAL_EXPORT="${SCRIPT_DIR}/clutch_skins.export.txt"

pick_default_ssh_key() {
  if [[ -n "${SSH_KEY}" ]]; then
    return
  fi
  for candidate in \
    "${HOME}/.ssh/id_ed25519_csgo_vps" \
    "${HOME}/.ssh/id_ed25519" \
    "${HOME}/.ssh/id_rsa"; do
    if [[ -f "${candidate}" ]]; then
      SSH_KEY="${candidate}"
      echo "Using SSH key: ${SSH_KEY}"
      return
    fi
  done
}

build_ssh_wrappers() {
  SSH_OPTS=(
    -o BatchMode=no
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
  )
  SCP_OPTS=(
    -o BatchMode=no
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
  )

  if [[ -n "${SSH_KEY}" ]]; then
    SSH_OPTS+=(-i "${SSH_KEY}")
    SCP_OPTS+=(-i "${SSH_KEY}")
  fi

  if [[ -n "${SSH_PASSWORD}" ]] && command -v sshpass >/dev/null 2>&1; then
    SSH_CMD=(sshpass -p "${SSH_PASSWORD}" ssh)
    SCP_CMD=(sshpass -p "${SSH_PASSWORD}" scp)
  else
    SSH_CMD=(ssh)
    SCP_CMD=(scp)
  fi
}

print_ssh_help() {
  echo "" >&2
  echo "SSH/SCP falhou. A VPS costuma exigir chave SSH (senha desativada)." >&2
  echo "" >&2
  echo "1) Teste login:" >&2
  echo "   ssh ${SSH_TARGET}" >&2
  echo "" >&2
  echo "2) Chave NOVA só para este servidor (não altera suas chaves atuais):" >&2
  echo "   ssh-keygen -t ed25519 -f \"\$HOME/.ssh/id_ed25519_csgo_vps\" -N \"\"" >&2
  echo "   ssh-copy-id -i \"\$HOME/.ssh/id_ed25519_csgo_vps.pub\" ${SSH_TARGET}" >&2
  echo "" >&2
  echo "3) Rode o sync com essa chave:" >&2
  echo "   CLUTCH_SSH_KEY=\"\$HOME/.ssh/id_ed25519_csgo_vps\" ./sync-clutch-skins-dev.sh" >&2
  echo "" >&2
  echo "4) Sem SSH agora — só baixar o arquivo:" >&2
  echo "   CLUTCH_FETCH_ONLY=1 ./sync-clutch-skins-dev.sh" >&2
  echo "   Envie ${LOCAL_EXPORT} via WinSCP/FileZilla para:" >&2
  echo "   ${REMOTE_PATH}" >&2
  echo "" >&2
  echo "5) Na VPS, depois do upload:" >&2
  echo "   sm_reloadclutchskins" >&2
}

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

cp -f "${LOCAL_TMP}" "${LOCAL_EXPORT}"
echo "Saved local copy: ${LOCAL_EXPORT} ($(wc -c < "${LOCAL_EXPORT}") bytes)"

if [[ "${FETCH_ONLY}" == "1" ]] || [[ "${FETCH_ONLY}" == "true" ]] || [[ "${FETCH_ONLY}" == "yes" ]]; then
  rm -f "${LOCAL_TMP}"
  echo "FETCH_ONLY — upload skipped."
  echo "Upload ${LOCAL_EXPORT} to ${SSH_TARGET}:${REMOTE_PATH}"
  exit 0
fi

pick_default_ssh_key
build_ssh_wrappers

echo "Testing SSH to ${SSH_TARGET} ..."
if ! "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "${SSH_TARGET}" "echo ok" >/dev/null 2>&1; then
  echo "SSH connection failed." >&2
  print_ssh_help
  rm -f "${LOCAL_TMP}"
  exit 1
fi

echo "Uploading to ${SSH_TARGET}:${REMOTE_PATH} ..."
if ! "${SCP_CMD[@]}" "${SCP_OPTS[@]}" "${LOCAL_TMP}" "${SSH_TARGET}:${REMOTE_PATH}.tmp"; then
  echo "SCP upload failed." >&2
  print_ssh_help
  rm -f "${LOCAL_TMP}"
  exit 1
fi

if ! "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "${SSH_TARGET}" "mv -f '${REMOTE_PATH}.tmp' '${REMOTE_PATH}' && chmod 644 '${REMOTE_PATH}'"; then
  echo "Remote mv failed." >&2
  print_ssh_help
  rm -f "${LOCAL_TMP}"
  exit 1
fi

rm -f "${LOCAL_TMP}"
echo "OK — synced. On server: sm_reloadclutchskins"
