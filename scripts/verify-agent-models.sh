#!/usr/bin/env bash
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
MODELS_ROOT="${CSGO_ROOT}/models/player/custom_player"
WEAPONS_DB="${CSGO_ROOT}/addons/sourcemod/data/sqlite/weapons.sq3"

echo "=== Agent models on disk ==="
echo "CSGO_ROOT: ${CSGO_ROOT}"
echo ""

if [[ ! -d "${MODELS_ROOT}" ]]; then
  echo "MISSING ${MODELS_ROOT}"
  echo ""
  echo "CS:GO agent .mdl files are required on the dedicated server."
  echo "They live under models/player/custom_player/ (Shattered Web+ agents)."
  echo ""
  echo "Note: Steam app 740 (dedicated server) does NOT include custom_player."
  echo "      app_update 740 validate alone will never create this folder."
  echo ""
  echo "Fix options:"
  echo "  1) On the VPS (downloads CS:GO client app 730, copies models only):"
  echo "     cd ~/api-csgo && ./scripts/install-agent-models.sh"
  echo "  2) From a PC with CS:GO installed:"
  echo "     local:  Steam/.../Counter-Strike Global Offensive/csgo/models/player/custom_player"
  echo "     server: ${CSGO_ROOT}/models/player/custom_player"
  echo "     scp -r custom_player csgo@server:${CSGO_ROOT}/models/player/"
  echo "  3) Mirror the same tree on your fastdl URL (or set CSGO_FASTDL_ROOT in install script)"
  exit 1
fi

count="$(find "${MODELS_ROOT}" -name '*.mdl' 2>/dev/null | wc -l | tr -d ' ')"
echo "OK  custom_player folder exists (${count} .mdl files)"

samples=(
  "tm_professional/tm_professional_varf5.mdl"
  "ctm_st6/ctm_st6_variantj.mdl"
  "tm_phoenix/tm_phoenix.mdl"
)

echo ""
echo "Sample paths:"
for rel in "${samples[@]}"; do
  full="${MODELS_ROOT}/${rel}"
  if [[ -f "${full}" ]]; then
    echo "  OK  models/player/custom_player/${rel}"
  else
    echo "  MISS models/player/custom_player/${rel}"
  fi
done

if [[ -f "${WEAPONS_DB}" ]] && command -v sqlite3 >/dev/null 2>&1; then
  echo ""
  echo "Equipped agent models (clutch_agents):"
  sqlite3 -separator '|' "${WEAPONS_DB}" \
    "SELECT steamid, t_model, ct_model FROM clutch_agents WHERE t_model != '' OR ct_model != '' LIMIT 20;" 2>/dev/null \
    | while IFS='|' read -r steam t ct; do
        for path in "${t}" "${ct}"; do
          [[ -z "${path}" ]] && continue
          rel="${path#models/player/custom_player/}"
          full="${CSGO_ROOT}/${path}"
          if [[ -f "${full}" ]]; then
            echo "  OK  ${steam} -> ${path}"
          else
            echo "  MISS ${steam} -> ${path}"
          fi
        done
      done || echo "  (clutch_agents table empty or missing)"
fi

echo ""
echo "If paths show MISS, agent equip will fall back to default model (no red ERROR)."
