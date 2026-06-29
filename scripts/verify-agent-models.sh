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
  echo "Fix options (SteamCMD cannot download CS:GO client on Linux):"
  echo "  1) PC with CS:GO Legacy — models are inside pak01_dir.vpk:"
  echo "     cd api-csgo && pip install vpk"
  echo "     python scripts/extract-agent-models-from-csgo.py"
  echo "     scp custom_player.tgz csgo@YOUR_VPS:/tmp/"
  echo "     VPS: ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz"
  echo "  2) One-shot from PC: VPS_HOST=csgo@YOUR_VPS ./scripts/push-agent-models-from-pc.sh"
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
