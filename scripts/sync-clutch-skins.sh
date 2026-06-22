#!/usr/bin/env bash
set -euo pipefail

# DEPRECATED — use sync-loadouts-from-site.sh (100% API, no files).
# Legacy: baixava export KeyValues e gravava clutch_skins.txt (v3 plugin ignores).
#
# Rode NA VPS do CS (ou cron): baixa export do site e grava clutch_skins.txt local.
# Não use sync-clutch-skins-dev.sh aqui — esse é PC → SCP.
#
# Env:
#   CLUTCH_SITE_URL      — URL pública do Next.js (ex. https://clutchclube.com)
#   CSGO_SKINS_SYNC_KEY  — igual ao site/.env
#   CLUTCH_SKINS_OUT     — opcional (default: SourceMod data)

SITE_URL="${CLUTCH_SITE_URL:-https://clutchclube.com}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
OUT="${CLUTCH_SKINS_OUT:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"
EXPORT_URL="${SITE_URL%/}/api/csgo/skins/export"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY is required" >&2
  exit 1
fi

TMP="${OUT}.tmp"
mkdir -p "$(dirname "${OUT}")"

echo "Fetching ${EXPORT_URL} ..."
HTTP_CODE="$(curl -sS -o "${TMP}" -w "%{http_code}" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  "${EXPORT_URL}" || echo "000")"

if [[ "${HTTP_CODE}" != "200" ]]; then
  rm -f "${TMP}"
  echo "Export failed (HTTP ${HTTP_CODE})." >&2
  echo "Deploy o site com /api/csgo/skins/export ou aponte CLUTCH_SITE_URL ao Next.js certo." >&2
  echo "Dev local (PC): use sync-clutch-skins-dev.sh no Windows, não na VPS." >&2
  exit 1
fi

if [[ ! -s "${TMP}" ]]; then
  echo "Export empty — equip skins on the site first." >&2
  rm -f "${TMP}"
  exit 1
fi

mv -f "${TMP}" "${OUT}"
chmod 644 "${OUT}" 2>/dev/null || true

echo "Synced $(wc -c < "${OUT}") bytes to ${OUT}"

if [[ "${CLUTCH_AUTO_RELOAD:-0}" == "1" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${SCRIPT_DIR}/reload-clutch-skins-ingame.sh" || true
fi