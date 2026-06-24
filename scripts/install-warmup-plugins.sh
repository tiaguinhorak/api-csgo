#!/usr/bin/env bash
# Instala plugins Clutch para servidor WARMUP (sem match tracker ranked).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo ">>> Warmup plugins (skins + gate + weapons — sem match tracker)"
bash "${REPO_ROOT}/scripts/install-nolobby-reservation.sh"
bash "${REPO_ROOT}/scripts/install-csgo-steamfix-engine.sh"
bash "${REPO_ROOT}/scripts/install-ptah.sh"
bash "${REPO_ROOT}/scripts/install-kgns-weapons.sh"
bash "${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh"
bash "${REPO_ROOT}/scripts/install-clutch-platform-gate.sh"
bash "${REPO_ROOT}/scripts/sync-weapons-cfg-from-site.sh" || true
bash "${REPO_ROOT}/scripts/sync-steam-allowlist.sh" || true
bash "${REPO_ROOT}/scripts/ensure-clutch-server-branding.sh" || true

echo ""
echo "Skins no warmup = mesma fonte que ranked: site (Postgres) → SQLite local."
echo "  bash scripts/sync-team-loadouts-warmup.sh   # após equipar no site"
echo "  bash scripts/reload-clutch-skins-ingame.sh"

echo ""
echo "Warmup plugins OK. Opcional: bash scripts/install-csgo-weaponstickers.sh"
echo "In-game: sm plugins list | grep clutch"
