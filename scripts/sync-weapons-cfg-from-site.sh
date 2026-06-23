#!/usr/bin/env bash
set -euo pipefail

# Regenerate weapons_english.cfg from site catalog + kgns GitHub base.
# Requires api-csgo running and CLUTCH_SITE_URL + CSGO_SKINS_SYNC_KEY in .env

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3001}"
URL="http://127.0.0.1:${PORT}/api/csgo/skins/sync-weapons-cfg"
KEY="${CSGO_SKINS_SYNC_KEY:-}"

if [[ -z "${KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY missing in .env" >&2
  exit 1
fi

echo ">>> POST ${URL}"
curl -sf -X POST "${URL}" \
  -H "x-skins-sync-key: ${KEY}" \
  -H "Content-Type: application/json" \
  | python3 -m json.tool 2>/dev/null || cat

echo ""
echo "Done. Reload weapons plugin in-game if skins still missing:"
echo "  sm plugins reload weapons"
echo "  sm_clutch_applyskins"
