#!/usr/bin/env bash
# Why did screen / srcds exit? Run on VPS as csgo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
PORT="${CSGO_RCON_PORT:-27015}"
SCREEN_NAME="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"
BOOT_LOG="${SERVER_ROOT}/csgo/clutch-srcds-boot.log"

echo "=== CS:GO srcds diagnose ==="
echo "SERVER_ROOT=${SERVER_ROOT}"
echo "SCREEN=${SCREEN_NAME}  PORT=${PORT}"
echo ""

echo "--- srcds_linux binary ---"
if [[ -f "${SERVER_ROOT}/bin/srcds_linux" ]]; then
  ls -la "${SERVER_ROOT}/bin/srcds_linux"
  ldd "${SERVER_ROOT}/bin/srcds_linux" 2>&1 | grep -i 'not found' || echo "(ldd: no missing libs)"
else
  echo "MISSING: ${SERVER_ROOT}/bin/srcds_linux"
  if [[ -d "${SERVER_ROOT}/bin" ]]; then
    echo "bin/ contents:"
    ls -la "${SERVER_ROOT}/bin" 2>/dev/null | head -15 || true
  fi
fi
echo ""

if [[ -f "${SERVER_ROOT}/game/bin/linuxsteamrt64/cs2" ]] || [[ -f "${SERVER_ROOT}/game/csgo/bin/linuxsteamrt64/cs2" ]]; then
  echo "WARN: CS2 binary detected — ./srcds_run -game csgo is likely wrong for this install."
  echo "      Use Valve cs2.sh or reinstall legacy CSGO dedicated (Steam app 740)."
  echo ""
fi

crash_files="$(find "${SERVER_ROOT}/csgo" -maxdepth 1 -name 'crash*' 2>/dev/null | head -3 || true)"
if [[ -n "${crash_files}" ]]; then
  echo "${crash_files}"
  echo "recent crash dumps above"
fi
echo ""

echo "--- srcds_run ---"
if [[ -x "${SERVER_ROOT}/srcds_run" ]]; then
  ls -la "${SERVER_ROOT}/srcds_run"
else
  echo "MISSING or not executable: ${SERVER_ROOT}/srcds_run"
fi
echo ""

echo "--- csgo dir ---"
if [[ -d "${SERVER_ROOT}/csgo" ]]; then
  ls -la "${SERVER_ROOT}/csgo" | head -5
else
  echo "MISSING: ${SERVER_ROOT}/csgo"
fi
echo ""

echo "--- screen -ls ---"
screen -ls 2>/dev/null || echo "(no screen sessions)"
echo ""

echo "--- port ${PORT} udp ---"
ss -ulnp 2>/dev/null | grep -E ":${PORT}\\s" || echo "(nothing on UDP ${PORT})"
echo ""

echo "--- srcds processes ---"
pgrep -u "$(id -u)" -af 'srcds|steam' 2>/dev/null || echo "(none)"
echo ""

if [[ -f "${BOOT_LOG}" ]]; then
  echo "--- tail ${BOOT_LOG} ---"
  tail -40 "${BOOT_LOG}"
  echo ""
fi

if [[ -f "${SERVER_ROOT}/csgo/console.log" ]]; then
  echo "--- tail csgo/console.log ---"
  tail -20 "${SERVER_ROOT}/csgo/console.log"
  echo ""
fi

echo "--- SourceMod errors (if any) ---"
ls -t "${SERVER_ROOT}/csgo/addons/sourcemod/logs"/errors_*.log 2>/dev/null | head -1 | xargs tail -15 2>/dev/null || echo "(no errors log)"
echo ""

echo "If srcds dies instantly, run:"
echo "  cd ~/api-csgo && bash scripts/test-srcds-foreground.sh"
