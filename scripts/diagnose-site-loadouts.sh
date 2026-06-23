#!/usr/bin/env bash
# Fetch equipped loadouts from production site API (debug empty clutch_team_loadout).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SITE_URL="${CLUTCH_SITE_URL:-${SITE_ORIGIN:-}}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"

if [[ -z "${SITE_URL}" ]]; then
  echo "ERROR: set CLUTCH_SITE_URL or SITE_ORIGIN in .env" >&2
  exit 1
fi
if [[ -z "${SYNC_KEY}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set" >&2
  exit 1
fi

SITE_URL="${SITE_URL%/}"
URL="${SITE_URL}/api/csgo/skins/equipped-loadouts"

echo "=== Site loadouts probe ==="
echo "URL: ${URL}"

HTTP_CODE="$(curl -s -o /tmp/clutch-site-loadouts.json -w '%{http_code}' \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Accept: application/json" \
  "${URL}")"

echo "HTTP ${HTTP_CODE}"
head -c 2000 /tmp/clutch-site-loadouts.json
echo ""

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "ERROR: site API failed — check CSGO_SKINS_SYNC_KEY matches site .env" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo ""
  echo "count: $(jq -r '.count // 0' /tmp/clutch-site-loadouts.json)"
  echo "sample weapons (team field):"
  jq -r '.loadouts[]? | .steamId as $s | .weapons[]? | "\($s) \(.team // "no-team") \(.weaponId) pk=\(.paintkit)"' \
    /tmp/clutch-site-loadouts.json | head -20
else
  echo "Install jq for parsed output: sudo apt install jq"
fi
