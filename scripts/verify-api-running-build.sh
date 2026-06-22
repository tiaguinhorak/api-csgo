#!/usr/bin/env bash
# Confirms port 3000 is served by the current dist/ build (not a stale node process).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT="${PORT:-3000}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:${PORT}}"
  echo "ERROR: dist/ missing — run: npm run build" >&2
  exit 1
fi

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "ERROR: dist build has no gloves player-sync — git too old?" >&2
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
if [[ -z "${SYNC_KEY}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

HEALTH="$(curl -sf "${API_URL}/health" 2>/dev/null || true)"
echo "health: ${HEALTH:-<no response>}"

PROBE="$(curl -sf -X POST "${API_URL}/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"steamId":"STEAM_1:0:0","weapons":[]}' 2>/dev/null || true)"

if [[ -z "${PROBE}" ]]; then
  echo "ERROR: no response from player-sync on ${API_URL}" >&2
  exit 1
fi

echo "player-sync probe: ${PROBE}"

if echo "${PROBE}" | grep -q '"gloves"'; then
  if echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
    echo "OK: running build matches dist (health + gloves field)."
  else
    echo "OK: player-sync has gloves field (health marker optional)."
  fi
  exit 0
fi

echo "ERROR: stale api on :${PORT} — dist has gloves sync but live API does not." >&2
echo "  Run: ./scripts/pm2-recover.sh" >&2
echo "  Or:  ./scripts/diagnose-port-3000.sh" >&2
exit 1
