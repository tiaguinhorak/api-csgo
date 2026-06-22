#!/usr/bin/env bash
set -euo pipefail

# Testa escrita na tabela gloves (player-sync) e mostra o resultado no SQLite.
#
# Uso:
#   cd ~/api-csgo && ./scripts/test-gloves-sync.sh STEAM_1:0:12345
#   ./scripts/test-gloves-sync.sh STEAM_1:0:12345 --clear

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

STEAM_ID="${1:-}"
MODE="${2:-apply}"
API_URL="${CLUTCH_API_URL:-http://127.0.0.1:3000}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
PREFIX="${WEAPONS_TABLE_PREFIX:-}"
TABLE="${PREFIX}gloves"
RESPONSE_FILE="/tmp/clutch-gloves-test.json"

if [[ -z "${STEAM_ID}" ]]; then
  echo "Usage: $0 STEAM_x:y:steamid [--clear]" >&2
  exit 1
fi

if [[ -z "${SYNC_KEY}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY not set in .env" >&2
  exit 1
fi

echo ">>> health"
HEALTH="$(curl -sf "${API_URL}/health" 2>/dev/null || true)"
if [[ -z "${HEALTH}" ]]; then
  echo "WARN: ${API_URL}/health unreachable — is pm2 running api-csgo?"
else
  echo "${HEALTH}"
fi

# Prefer player-sync probe over /health marker (orphan node on :3000 may lack glovesPlayerSync).
if [[ -n "${SYNC_KEY}" ]]; then
  PROBE="$(curl -sf -X POST "${API_URL}/api/csgo/skins/player-sync" \
    -H "x-skins-sync-key: ${SYNC_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"steamId":"STEAM_1:0:0","weapons":[]}' 2>/dev/null || true)"
  if [[ -n "${PROBE}" ]] && echo "${PROBE}" | grep -q '"gloves"'; then
    echo "OK: player-sync has gloves field."
  elif [[ -n "${HEALTH}" ]] && echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
    echo "OK: /health has glovesPlayerSync marker."
  else
    echo ""
    echo "ERROR: API missing gloves sync (stale process on :3000?)."
    echo "  Run: cd ~/api-csgo && ./scripts/pm2-recover.sh"
    exit 1
  fi
elif [[ -z "${HEALTH}" ]] || ! echo "${HEALTH}" | grep -q 'glovesPlayerSync'; then
  echo ""
  echo "ERROR: cannot verify gloves sync (no CSGO_SKINS_SYNC_KEY and /health has no marker)."
  exit 1
fi

if [[ "${MODE}" == "--clear" ]]; then
  BODY="$(cat <<EOF
{"steamId":"${STEAM_ID}","weapons":[],"clearWeaponIds":["leather_handwraps"]}
EOF
)"
  EXPECT_ACTION="clear"
else
  BODY="$(cat <<EOF
{"steamId":"${STEAM_ID}","weapons":[{"weaponId":"leather_handwraps","paintkit":10010,"wear":0.15,"defIndex":5032}]}
EOF
)"
  EXPECT_ACTION="apply"
fi

echo ""
echo "POST ${API_URL}/api/csgo/skins/player-sync"
HTTP="$(curl -sS -o "${RESPONSE_FILE}" -w "%{http_code}" \
  -X POST "${API_URL}/api/csgo/skins/player-sync" \
  -H "x-skins-sync-key: ${SYNC_KEY}" \
  -H "Content-Type: application/json" \
  -d "${BODY}")"
echo "HTTP ${HTTP}"
cat "${RESPONSE_FILE}"
echo ""

if [[ "${HTTP}" != "200" ]]; then
  echo "ERROR: player-sync failed (HTTP ${HTTP})" >&2
  exit 1
fi

if ! grep -q '"gloves"' "${RESPONSE_FILE}"; then
  echo ""
  echo "ERROR: response has no 'gloves' field — api-csgo build is too old." >&2
  echo "  cd ~/api-csgo && ./scripts/deploy-vps.sh" >&2
  exit 1
fi

if [[ "${EXPECT_ACTION}" == "apply" ]]; then
  if grep -q '"updated":false' "${RESPONSE_FILE}"; then
    echo ""
    echo "ERROR: updated=false — gloves were not written to SQLite." >&2
    echo "  Check: pm2 logs api-csgo --lines 30" >&2
    exit 1
  fi
  if ! grep -q '"action":"apply"' "${RESPONSE_FILE}"; then
    echo ""
    echo "WARN: expected gloves.action=apply — see response above." >&2
  fi
fi

if command -v sqlite3 >/dev/null 2>&1 && [[ -f "${DB_PATH}" ]]; then
  echo "--- ${TABLE} ---"
  STEAM_SUFFIX="${STEAM_ID#STEAM_1:}"
  if [[ "${STEAM_SUFFIX}" == "${STEAM_ID}" ]]; then
    STEAM_SUFFIX="${STEAM_ID#STEAM_0:}"
  fi
  ROWS="$(sqlite3 "${DB_PATH}" "SELECT steamid,t_group,t_glove,ct_group,ct_glove FROM ${TABLE} WHERE steamid LIKE '%${STEAM_SUFFIX}%';")"
  if [[ -z "${ROWS}" && "${EXPECT_ACTION}" == "apply" ]]; then
    echo "(empty — sync did not persist gloves)"
    exit 1
  fi
  echo "${ROWS}"
fi
