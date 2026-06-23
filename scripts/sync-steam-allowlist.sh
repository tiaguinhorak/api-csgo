#!/usr/bin/env bash
# Sincroniza allowlist Steam (site → SQLite) para clutch_platform_gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f dist/services/steam-allowlist-sync.js ]]; then
  echo "ERROR: dist missing — run npm run build first" >&2
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${CLUTCH_SITE_URL:-}" || -z "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo "WARN: CLUTCH_SITE_URL e CSGO_SKINS_SYNC_KEY necessários no .env" >&2
  exit 1
fi

node <<'NODE'
require('dotenv').config();
const { runSteamAllowlistSync } = require('./dist/services/steam-allowlist-sync');
runSteamAllowlistSync()
  .then((n) => {
    console.log(`[steam-allowlist] synced ${n} account(s)`);
    process.exit(0);
  })
  .catch((err) => {
    console.error('[steam-allowlist]', err instanceof Error ? err.message : err);
    process.exit(1);
  });
NODE
