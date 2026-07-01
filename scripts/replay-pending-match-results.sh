#!/usr/bin/env bash
# Re-send finished clutch_match_live rows that match api-csgo store.json (after fixing CLUTCH_SITE_URL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
source_clutch_env "${REPO_ROOT}/.env"

if [[ ! -f "${REPO_ROOT}/dist/tools/replay-pending-results.js" ]]; then
  echo "Building api-csgo (dist/tools/replay-pending-results.js missing)..."
  npm run build
fi

node "${REPO_ROOT}/dist/tools/replay-pending-results.js" "$@"
