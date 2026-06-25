#!/usr/bin/env bash
# csgo_weaponstickers: SDK sticker render + overrideview. Bridge owns DB sync (clutch_weaponstickers).
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CFG="${CSGO_ROOT}/cfg/sourcemod/csgo_weaponstickers.cfg"
mkdir -p "$(dirname "${CFG}")"

cat > "${CFG}" <<'EOF'
// Clutch bridge syncs clutch_weaponstickers + mirrors active team to weaponstickers1.
// csgo_weaponstickers.smx applies sticker visuals via game SDK (CS_SetWeaponSticker).
sm_weaponstickers_enabled "1"
sm_weaponstickers_overrideview "1"
sm_weaponstickers_updateviewmodel "1"
sm_weaponstickers_reusetime "0"
sm_weaponstickers_flag ""
sm_weaponstickers_inactive_days "0"
EOF

echo "Written ${CFG}"
echo "Ensure csgo_weaponstickers.smx is loaded: sm plugins load csgo_weaponstickers"
echo "Reload in-game: exec sourcemod/csgo_weaponstickers.cfg"
