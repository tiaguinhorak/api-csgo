#!/usr/bin/env bash
set -euo pipefail

# DEPRECATED: use this script instead of sync-clutch-skins.sh (no files on disk).
#
# Pulls equipped loadouts from site Postgres via site API → api-csgo → weapons SQLite.
#
# Env (api-csgo .env):
#   CLUTCH_SITE_URL or SITE_ORIGIN — public site URL (e.g. https://clutchclube.com)
#   CSGO_SKINS_SYNC_KEY — same as site
#
# Usage on VPS:
#   cd ~/api-csgo && ./scripts/sync-loadouts-from-site.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
API_KEY="${API_KEY:-${CSGO_API_KEY:-}}"

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY is required" >&2
  exit 1
fi

AUTH_HEADER=(-H "x-skins-sync-key: ${SYNC_KEY}")
if [[ -n "${API_KEY}" ]]; then
  AUTH_HEADER+=(-H "x-api-key: ${API_KEY}")
fi

echo "POST ${API_URL}/api/csgo/skins/sync-from-site ..."
HTTP_CODE="$(curl -sS -o /tmp/clutch-sync-from-site.json -w "%{http_code}" \
  -X POST "${API_URL}/api/csgo/skins/sync-from-site" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json")"

cat /tmp/clutch-sync-from-site.json
echo ""

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "Failed (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

echo "OK — sync-from-site completed (no clutch_skins.txt)."
