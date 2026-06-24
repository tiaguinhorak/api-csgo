#!/usr/bin/env bash
# Warmup VPS: regenerate weapons_english.cfg without local api-csgo HTTP.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f dist/services/sync-weapons-cfg-file.js ]]; then
  echo "ERROR: dist missing — run: npm run build" >&2
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

echo "=== Warmup weapons_english.cfg sync (node, no HTTP) ==="

node <<'NODE'
require('dotenv').config();
const { syncWeaponsCfgFromSite } = require('./dist/services/sync-weapons-cfg-file');

(async () => {
  const result = await syncWeaponsCfgFromSite();
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) {
    process.exit(1);
  }
})();
NODE

echo ""
echo "Done. Reload in-game:"
echo "  sm plugins reload weapons"
echo "  sm_clutch_applyskins"
