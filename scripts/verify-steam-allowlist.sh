#!/usr/bin/env bash
# Verify platform gate allowlist sync (site → api-csgo → SQLite → clutch_platform_gate).
# Usage: bash scripts/verify-steam-allowlist.sh [steam64_or_account_id]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_PATH="${WEAPONS_DB_PATH:-}"
if [[ -z "${DB_PATH}" ]]; then
  DB_PATH="$(node -e "const { getWeaponsDbPath } = require('./dist/services/weapons-db-path'); try { console.log(getWeaponsDbPath()); } catch(e) { console.error(e.message); process.exit(1); }" 2>/dev/null || true)"
fi
if [[ -z "${DB_PATH}" ]]; then
  for c in \
    /home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3 \
    /home/csgo/server/csgo/addons/sourcemod/data/sqlite/local.sq3; do
    if [[ -f "${c}" ]]; then
      DB_PATH="${c}"
      break
    fi
  done
fi

echo "=== Steam allowlist verify ==="
echo "DB: ${DB_PATH:-NOT FOUND}"

if [[ -n "${CLUTCH_SITE_URL:-}" ]]; then
  echo "CLUTCH_SITE_URL=${CLUTCH_SITE_URL}"
else
  echo "WARN: CLUTCH_SITE_URL not set in api-csgo .env"
fi

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo "CSGO_SKINS_SYNC_KEY=set"
else
  echo "WARN: CSGO_SKINS_SYNC_KEY not set — sync disabled"
fi

if [[ -n "${CLUTCH_SITE_URL:-}" && -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo ""
  echo "--- Site API ---"
  curl -fsSL -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    "${CLUTCH_SITE_URL%/}/api/csgo/steam-allowlist" | head -c 500
  echo ""
fi

if [[ -n "${DB_PATH}" && -f "${DB_PATH}" ]]; then
  echo ""
  echo "--- SQLite clutch_steam_allowlist ---"
  if command -v sqlite3 >/dev/null 2>&1; then
    count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM clutch_steam_allowlist;" 2>/dev/null || echo "?")"
    echo "row count: ${count}"
    sqlite3 "${DB_PATH}" "SELECT account_id FROM clutch_steam_allowlist ORDER BY account_id LIMIT 20;" 2>/dev/null || true
    if [[ -n "${1:-}" ]]; then
      arg="${1}"
      if [[ "${arg}" =~ ^[0-9]{17}$ ]]; then
        # steam64 → account id
        acc="$(node -e "console.log(Number(BigInt('${arg}') - BigInt('76561197960265728')))")"
      else
        acc="${arg}"
      fi
      echo "lookup account_id=${acc}:"
      sqlite3 "${DB_PATH}" "SELECT 1 FROM clutch_steam_allowlist WHERE account_id=${acc};" 2>/dev/null || true
    fi
  else
    echo "(install sqlite3 for local queries)"
  fi
else
  echo "WARN: weapons SQLite not found"
fi

echo ""
echo "In server console: sm_clutch_gate_check <player>"
