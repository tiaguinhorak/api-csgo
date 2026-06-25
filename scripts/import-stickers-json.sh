#!/usr/bin/env bash
# Import stickers JSON on VPS (file copied from dev PC or fetch-site-stickers output).
#
# Usage on VPS:
#   bash scripts/import-stickers-json.sh /tmp/clutch-site-stickers.json
#   bash scripts/import-stickers-json.sh /tmp/clutch-dev-stickers-equipped.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="${1:-}"

if [[ -z "${INPUT}" || ! -f "${INPUT}" ]]; then
  echo "Usage: $0 <stickers-json-file>" >&2
  echo "Expected format: { \"stickers\": [ { \"steamId\", \"entries\": [...] } ] }" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${REPO_ROOT}/dist/services/stickers-db-sync.js" ]]; then
  echo "Run: npm run build" >&2
  exit 1
fi

# Normalize site equipped response → import format
NORMALIZED="/tmp/clutch-stickers-import.json"
if command -v jq >/dev/null 2>&1; then
  if jq -e '.stickers' "${INPUT}" >/dev/null 2>&1; then
    cp -f "${INPUT}" "${NORMALIZED}"
  else
    echo "ERROR: JSON must contain .stickers array" >&2
    exit 1
  fi
else
  cp -f "${INPUT}" "${NORMALIZED}"
fi

node "${SCRIPT_DIR}/run-import-site-stickers.cjs" "${NORMALIZED}"

echo ""
echo "In screen: sm_clutch_refresh_stickers \"STEAM_0:0:203852188\""
