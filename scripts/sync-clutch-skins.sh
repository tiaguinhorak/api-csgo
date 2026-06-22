#!/usr/bin/env bash
set -euo pipefail

# Pull equipped skins KeyValues from clutchclube and write clutch_skins.txt for SourceMod.
#
# Env:
#   CLUTCH_SITE_URL      — e.g. https://clutchclube.com (no trailing slash)
#   CSGO_SKINS_SYNC_KEY  — same value as site CSGO_SKINS_SYNC_KEY
#   CLUTCH_SKINS_OUT     — optional output path (default: SourceMod data on VPS)

SITE_URL="${CLUTCH_SITE_URL:-https://clutchclube.com}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
OUT="${CLUTCH_SKINS_OUT:-/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt}"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY is required" >&2
  exit 1
fi

TMP="${OUT}.tmp"
mkdir -p "$(dirname "${OUT}")"

curl -fsS \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  "${SITE_URL}/api/csgo/skins/export" \
  -o "${TMP}"

if [[ ! -s "${TMP}" ]]; then
  echo "Export empty or failed" >&2
  rm -f "${TMP}"
  exit 1
fi

mv -f "${TMP}" "${OUT}"
chmod 644 "${OUT}" 2>/dev/null || true

echo "Synced $(wc -c < "${OUT}") bytes to ${OUT}"
