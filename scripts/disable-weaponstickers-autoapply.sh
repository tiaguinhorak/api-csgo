#!/usr/bin/env bash
# Disable csgo_weaponstickers auto-apply — conflicts with z_clutch_skins_bridge (smear/double apply).
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CFG="${CSGO_ROOT}/cfg/sourcemod/csgo_weaponstickers.cfg"
mkdir -p "$(dirname "${CFG}")"

cat > "${CFG}" <<'EOF'
// Clutch bridge applies stickers from clutch_weaponstickers (per TR/CT).
// Keep csgo_weaponstickers DISABLED — dual apply causes smeared/wrong stickers.
sm_weaponstickers_enabled "0"
sm_weaponstickers_overrideview "0"
sm_weaponstickers_updateviewmodel "0"
sm_weaponstickers_reusetime "0"
sm_weaponstickers_flag ""
sm_weaponstickers_inactive_days "0"
EOF

echo "Written ${CFG}"
echo "In screen run: exec sourcemod/csgo_weaponstickers.cfg"
echo "Unload conflicting plugin: sm plugins unload csgo_weaponstickers"
