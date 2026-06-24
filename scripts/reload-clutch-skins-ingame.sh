#!/usr/bin/env bash
set -euo pipefail

# Recarrega plugins Clutch no srcds via screen.
#
# Uso na VPS:
#   ./scripts/reload-clutch-skins-ingame.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM_PLUGINS="${CSGO_ROOT}/addons/sourcemod/plugins"

EXPECTED_BRIDGE_VERSION="$(grep -E '#define PLUGIN_VERSION' "${REPO_ROOT}/sourcemod/clutch_skins_bridge.sp" | sed 's/.*"\(.*\)".*/\1/')"
EXPECTED_GLOVES_VERSION="$(grep -E '#define PLUGIN_VERSION' "${REPO_ROOT}/sourcemod/z_clutch_gloves.sp" | sed 's/.*"\(.*\)".*/\1/')"

resolve_screen_session() {
  local preferred="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"
  local line full

  if screen -ls 2>/dev/null | grep -qF ".${preferred}"; then
    full="$(screen -ls 2>/dev/null | grep -F ".${preferred}" | head -1 | awk '{print $1}')"
    if [[ -n "${full}" ]]; then
      echo "${full}"
      return 0
    fi
  fi

  while IFS= read -r line; do
    if [[ "${line}" == *"(Detached)"* ]] && [[ "${line}" == *"csgo-"* ]]; then
      full="$(echo "${line}" | awk '{print $1}')"
      if [[ -n "${full}" ]]; then
        echo "${full}"
        return 0
      fi
    fi
  done < <(screen -ls 2>/dev/null || true)

  return 1
}

plugin_file_exists() {
  [[ -f "${SM_PLUGINS}/${1}.smx" ]]
}

FULL_SCREEN="$(resolve_screen_session || true)"
if [[ -z "${FULL_SCREEN}" ]]; then
  echo "No CS screen session found (server may be offline)." >&2
  echo "" >&2
  screen -ls 2>/dev/null || echo "(screen -ls failed)" >&2
  echo "" >&2
  echo "Start CS first: bash scripts/start-csgo-screen.sh" >&2
  exit 1
fi

# Warmup: always re-sync DB from the site before reload so kgns weapons/gloves
# tables hold the latest loadout (otherwise kgns serves stale/vanilla items).
if [[ "${WARMUP_VPS:-0}" == "1" && -f "${REPO_ROOT}/scripts/sync-team-loadouts-warmup.sh" ]]; then
  echo ">>> Warmup: syncing loadouts from site before reload..."
  bash "${REPO_ROOT}/scripts/sync-team-loadouts-warmup.sh" || \
    echo "WARN: sync-team-loadouts-warmup.sh failed — kgns table may be stale." >&2
fi

echo "Using screen session: ${FULL_SCREEN}"

send_cmd() {
  local cmd="$1"
  local wait="${2:-0.4}"
  echo ">>> ${cmd}"
  screen -S "${FULL_SCREEN}" -p 0 -X stuff "${cmd}^M"
  sleep "${wait}"
}

send_plugin() {
  local name="$1"
  if ! plugin_file_exists "${name}"; then
    echo ">>> skip ${name}.smx (not installed)"
    return 0
  fi
  send_cmd "sm plugins reload ${name}" 0.5
}

# weapons.smx must reload BEFORE bridge so patched natives register first
send_cmd "sm plugins reload weapons" 1.2
send_cmd "sm plugins info weapons" 0.5
send_cmd "sm plugins unload z_clutch_skins_bridge" 0.8
send_cmd "sm plugins unload z_clutch_gloves" 0.5
send_cmd "sm plugins load z_clutch_gloves" 1.0
send_cmd "sm plugins info z_clutch_gloves" 0.5
send_cmd "sm plugins load z_clutch_skins_bridge" 1.0
send_cmd "sm plugins reload z_clutch_skins_bridge" 1.0
send_cmd "sm plugins info z_clutch_skins_bridge" 0.5
send_plugin "clutch_platform_gate"

if [[ "${WARMUP_VPS:-0}" != "1" ]] && plugin_file_exists "clutch_match_tracker"; then
  send_plugin "clutch_match_tracker"
fi

send_cmd "clutch_gloves_debug 1" 0.3
send_cmd "clutch_skins_debug 1" 0.3

if [[ "${WARMUP_VPS:-0}" == "1" ]]; then
  echo "Warmup: applying skins after plugin reload..."
  send_cmd "sm_clutch_gloves_refresh" 1.0
  send_cmd "sm_clutch_gloves_apply" 0.8
  send_cmd "sm_clutch_applyskins" 2.0
fi

echo ""
echo "Plugins reloaded. Connect in-game FIRST (Steam auth must be ready, not auth-pending)."
if [[ "${WARMUP_VPS:-0}" != "1" ]]; then
  echo "Then in server console:"
  echo "  sm_clutch_gloves_refresh"
  echo "  sm_clutch_applyskins"
  echo "  mp_restartgame 1"
fi
echo ""
echo "Expect z_clutch_gloves Version: ${EXPECTED_GLOVES_VERSION}"
echo "       z_clutch_skins_bridge Version: ${EXPECTED_BRIDGE_VERSION}"
