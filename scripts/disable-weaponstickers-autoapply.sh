#!/usr/bin/env bash
# Disable csgo_weaponstickers auto-apply — z_clutch_skins_bridge owns sticker rendering.
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CFG="${CSGO_ROOT}/cfg/sourcemod/csgo_weaponstickers.cfg"
mkdir -p "$(dirname "${CFG}")"

cat > "${CFG}" <<'EOF'
// Clutch: bridge reads clutch_weaponstickers (per TR/CT). Do not auto-apply stale plugin cache.
sm_weaponstickers_enabled "0"
sm_weaponstickers_overrideview "0"
sm_weaponstickers_updateviewmodel "0"
sm_weaponstickers_reusetime "0"
sm_weaponstickers_inactive_days "0"
EOF

echo "Written ${CFG}"
echo "Reload in-game via screen (not bash):"
echo "  cd ~/api-csgo && bash scripts/reload-clutch-skins-ingame.sh"
echo "Or attach screen and run: exec sourcemod/csgo_weaponstickers.cfg"
