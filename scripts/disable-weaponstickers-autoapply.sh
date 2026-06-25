#!/usr/bin/env bash
# csgo_weaponstickers: auto-apply OFF (bridge owns apply). Plugin stays loaded for CS_SetWeaponSticker native.
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CFG="${CSGO_ROOT}/cfg/sourcemod/csgo_weaponstickers.cfg"
mkdir -p "$(dirname "${CFG}")"

cat > "${CFG}" <<'EOF'
// Clutch bridge applies stickers from clutch_weaponstickers (per TR/CT).
// Keep auto-apply DISABLED — dual apply causes smeared/wrong stickers.
// csgo_weaponstickers.smx must stay LOADED for CS_SetWeaponSticker native.
sm_weaponstickers_enabled "0"
sm_weaponstickers_overrideview "0"
sm_weaponstickers_updateviewmodel "0"
sm_weaponstickers_reusetime "0"
sm_weaponstickers_flag ""
sm_weaponstickers_inactive_days "0"
EOF

echo "Written ${CFG}"
echo "In screen run: exec sourcemod/csgo_weaponstickers.cfg"
echo "Ensure plugin is loaded: sm plugins load csgo_weaponstickers"
