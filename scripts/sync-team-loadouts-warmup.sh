#!/usr/bin/env bash
# Warmup VPS: site → SQLite local (sem api-csgo na mesma máquina).
# Usa node dist (player-sync logic) em vez de HTTP 127.0.0.1:3000.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f dist/services/weapons-db-sync.js ]]; then
  echo "ERROR: dist missing — run: npm install && npm run build" >&2
  exit 1
fi

# Warmup uses compiled JS — rebuild when TypeScript sync logic changed.
if [[ ! -f dist/services/weapons-db-map.js ]] \
  || [[ src/services/weapons-db-map.ts -nt dist/services/weapons-db-map.js ]] \
  || [[ src/services/weapons-db-sync.ts -nt dist/services/weapons-db-sync.js ]]; then
  echo ">>> Building api-csgo (sync services changed)..."
  npm run build
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_PATH="${WEAPONS_DB_PATH:-/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3}"
JSON_FILE="/tmp/clutch-site-loadouts.json"

echo "=== Warmup loadout sync (site → local SQLite) ==="
echo "DB: ${DB_PATH}"

bash "${REPO_ROOT}/scripts/fetch-site-loadouts.sh" "${JSON_FILE}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required — apt install jq (as root/clutch)" >&2
  exit 1
fi

node <<'NODE'
(async () => {
require('dotenv').config();
const fs = require('fs');
const { syncPlayerLoadoutToWeaponsDb } = require('./dist/services/weapons-db-sync');

const jsonPath = process.env.CLUTCH_LOADOUT_JSON || '/tmp/clutch-site-loadouts.json';
const raw = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const loadouts = raw.loadouts || [];
let ok = 0;
let err = 0;

for (const row of loadouts) {
  if (!row?.steamId || !Array.isArray(row.weapons)) continue;
  try {
    const result = await syncPlayerLoadoutToWeaponsDb(row.steamId, row.weapons);
    ok += 1;
    console.log(
      `[warmup-loadout] OK ${row.steamId} weapons=${row.weapons.length} columns=${result.columns}`,
    );
  } catch (e) {
    err += 1;
    console.error(`[warmup-loadout] FAIL ${row.steamId}:`, e instanceof Error ? e.message : e);
  }
}

console.log(`[warmup-loadout] done synced=${ok} errors=${err} total=${loadouts.length}`);
if (ok === 0 && loadouts.length > 0) process.exit(1);
})();
NODE

echo ""
echo ">>> clutch_team_loadout"
if [[ -f "${DB_PATH}" ]]; then
  sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS total FROM clutch_team_loadout;"
  sqlite3 "${DB_PATH}" \
    "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout ORDER BY steamid, team LIMIT 20;"
fi

echo ""
echo ">>> kgns weapons row (knife index + bayonet paint)"
if [[ -f "${DB_PATH}" ]]; then
  sqlite3 "${DB_PATH}" \
    "SELECT steamid, knife, bayonet, deagle, ak47 FROM weapons WHERE steamid LIKE '%203852188%' OR steamid LIKE '%407704376%' LIMIT 4;"
fi

echo ""
echo ">>> gloves row"
if [[ -f "${DB_PATH}" ]]; then
  sqlite3 "${DB_PATH}" \
    "SELECT steamid, t_group, t_glove, ct_group, ct_glove FROM gloves WHERE steamid LIKE '%203852188%' OR steamid LIKE '%407704376%' LIMIT 4;"
fi

echo ""
echo ">>> stage + apply in-game (same as ranked player-sync)"
if bash "${REPO_ROOT}/scripts/stage-and-apply-loadouts-in-game.sh"; then
  echo "In-game apply OK."
else
  echo "WARN: in-game apply failed — CS offline? Run: bash scripts/reload-clutch-skins-ingame.sh"
fi
