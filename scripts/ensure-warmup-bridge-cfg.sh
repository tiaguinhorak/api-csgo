#!/usr/bin/env bash
# Warmup: apply skins immediately (no defer until match end).
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
CFG="${CSGO_ROOT}/cfg/sourcemod/clutch_skins_bridge.cfg"

if [[ ! -f "${CFG}" ]]; then
  echo "WARN: ${CFG} not found — run install-clutch-skins-bridge.sh first" >&2
  exit 0
fi

if grep -q 'clutch_skins_defer_live' "${CFG}"; then
  sed -i 's|^clutch_skins_defer_live.*|clutch_skins_defer_live "0"|g' "${CFG}"
else
  printf '\nclutch_skins_defer_live "0"\n' >> "${CFG}"
fi

if grep -q 'clutch_skins_debug' "${CFG}"; then
  sed -i 's|^clutch_skins_debug.*|clutch_skins_debug "1"|g' "${CFG}"
fi

# CS console treats # as a command — remove invalid lines from old cfgs.
sed -i '/^#/d' "${CFG}" 2>/dev/null || true

echo "OK: warmup bridge cfg — defer_live=0, once_per_match=0 (re-read DB every spawn)"

if grep -q 'clutch_skins_once_per_match' "${CFG}"; then
  sed -i 's|^clutch_skins_once_per_match.*|clutch_skins_once_per_match "0"|g' "${CFG}"
else
  printf '\nclutch_skins_once_per_match "0"\n' >> "${CFG}"
fi
