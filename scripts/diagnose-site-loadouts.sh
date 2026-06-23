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

echo "=== Site loadouts probe ==="
bash "${REPO_ROOT}/scripts/fetch-site-loadouts.sh" /tmp/clutch-site-loadouts.json
head -c 2000 /tmp/clutch-site-loadouts.json
echo ""

if command -v jq >/dev/null 2>&1; then
  echo ""
  echo "count: $(jq -r '.count // 0' /tmp/clutch-site-loadouts.json)"
  echo "sample weapons (team field):"
  jq -r '.loadouts[]? | .steamId as $s | .weapons[]? | "\($s) \(.team // "no-team") \(.weaponId) pk=\(.paintkit)"' \
    /tmp/clutch-site-loadouts.json | head -20
else
  echo "Install jq for parsed output: sudo apt install jq"
fi
