#!/usr/bin/env bash
set -euo pipefail

# Compila e instala clutch_platform_gate (bloqueia Steam sem conta na plataforma).
#
# Uso:
#   cd ~/api-csgo && git pull
#   ./scripts/install-clutch-platform-gate.sh

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"

detect_live_csgo_root() {
  local pid cwd exe dir
  pid="$(pgrep -n -x srcds_linux 2>/dev/null || pgrep -n -f 'srcds_linux.*csgo' 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
  if [[ -n "${cwd}" && -d "${cwd}/addons/sourcemod/plugins" ]]; then
    echo "${cwd}"
    return 0
  fi
  exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
  dir="$(dirname "${exe}")"
  if [[ -d "${dir}/csgo/addons/sourcemod/plugins" ]]; then
    echo "${dir}/csgo"
    return 0
  fi
  if [[ -d "${dir}/addons/sourcemod/plugins" ]]; then
    echo "${dir}"
    return 0
  fi
  return 1
}

LIVE_ROOT="$(detect_live_csgo_root || true)"
if [[ -n "${LIVE_ROOT}" && "${LIVE_ROOT}" != "${CSGO_ROOT}" ]]; then
  echo "srcds is running from ${LIVE_ROOT} (not default ${CSGO_ROOT}) — installing there."
  CSGO_ROOT="${LIVE_ROOT}"
fi

SM="${CSGO_ROOT}/addons/sourcemod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SP_SRC="${REPO_ROOT}/sourcemod/clutch_platform_gate.sp"

if [[ ! -f "${SP_SRC}" ]]; then
  echo "Missing ${SP_SRC} — git pull em ~/api-csgo" >&2
  exit 1
fi

if [[ ! -d "${SM}/scripting" ]]; then
  echo "SourceMod not found at ${SM}" >&2
  exit 1
fi

SPCOMP="${SM}/scripting/spcomp"
if [[ ! -x "${SPCOMP}" ]]; then
  SPCOMP="${SM}/scripting/spcomp64"
fi
if [[ ! -x "${SPCOMP}" ]]; then
  echo "spcomp not found in ${SM}/scripting/" >&2
  exit 1
fi

chmod +x "${SCRIPT_DIR}/install-clutch-platform-gate.sh" 2>/dev/null || true

cp "${SP_SRC}" "${SM}/scripting/clutch_platform_gate.sp"
"${SPCOMP}" "${SM}/scripting/clutch_platform_gate.sp" -o"${SM}/plugins/clutch_platform_gate.smx"

echo "Installed ${SM}/plugins/clutch_platform_gate.smx"
echo ""
echo "api-csgo must sync allowlist from site (restart api-csgo after deploy)."
echo ""
echo "Attach to the CS:GO server screen and run in SERVER console (not bash):"
echo "  screen -r"
echo "  sm plugins load clutch_platform_gate"
echo "  sm plugins list clutch"
echo ""
echo "After first load, updates use: sm plugins reload clutch_platform_gate"
