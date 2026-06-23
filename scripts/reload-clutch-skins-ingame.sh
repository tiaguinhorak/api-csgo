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
    if [[ "${line}" == *"(Detached)"* ]] && [[ "${line}" == *"csgo-clutch"* ]]; then
      full="$(echo "${line}" | awk '{print $1}')"
      if [[ -n "${full}" ]]; then
        echo "${full}"
        return 0
      fi
    fi
  done < <(screen -ls 2>/dev/null || true)

  return 1
}

FULL_SCREEN="$(resolve_screen_session || true)"
if [[ -z "${FULL_SCREEN}" ]]; then
  echo "No CS screen session found (server may be offline)." >&2
  echo "" >&2
  screen -ls 2>/dev/null || echo "(screen -ls failed)" >&2
  echo "" >&2
  echo "Start CS first, then re-run:" >&2
  echo "  bash scripts/reload-clutch-skins-ingame.sh" >&2
  echo "" >&2
  echo "Or attach manually and run one command per line:" >&2
  echo "  screen -r csgo-clutch-#1" >&2
  echo "  sm plugins load z_clutch_gloves" >&2
  echo "  sm plugins load z_clutch_skins_bridge" >&2
  echo "  sm plugins info z_clutch_gloves" >&2
  echo "  sm plugins info z_clutch_skins_bridge" >&2
  exit 1
fi

echo "Using screen session: ${FULL_SCREEN}"

send_cmd() {
  local cmd="$1"
  echo ">>> ${cmd}"
  screen -S "${FULL_SCREEN}" -p 0 -X stuff "${cmd}^M"
  sleep 0.4
}

# reload fails when plugin was never loaded; load picks up new .smx from plugins/
send_plugin() {
  local name="$1"
  send_cmd "sm plugins reload ${name}"
  send_cmd "sm plugins load ${name}"
}

send_cmd "sm plugins reload weapons"
send_cmd "sm plugins info weapons"
send_plugin "z_clutch_gloves"
send_cmd "sm plugins info z_clutch_gloves"
send_plugin "z_clutch_skins_bridge"
send_cmd "sm plugins info z_clutch_skins_bridge"
send_cmd "clutch_gloves_debug 1"
send_cmd "clutch_skins_debug 1"
send_cmd "sm_reloadclutchskins"
send_cmd "sm_clutch_applyskins"

echo ""
echo "Done. Expect z_clutch_gloves Version: ${EXPECTED_GLOVES_VERSION}"
echo "       z_clutch_skins_bridge Version: ${EXPECTED_BRIDGE_VERSION}"
echo ""
echo "If still 'not loaded', run install first:"
echo "  ./scripts/install-clutch-skins-bridge.sh"
echo "Then re-run this script or: sm plugins load z_clutch_gloves / z_clutch_skins_bridge"
echo "If load fails, check: ./scripts/verify-clutch-skins-bridge.sh"
echo "Respawn in-game after apply."
