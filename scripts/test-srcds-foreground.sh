#!/usr/bin/env bash
# Run srcds in foreground for ~25s to capture crash reason (no screen).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
PORT="${CSGO_RCON_PORT:-27015}"
RCON="${CSGO_RCON_PASSWORD:-clutchclube}"
GSLT="${CSGO_GSLT_TOKEN:-}"
MAP="${CSGO_START_MAP:-de_dust2}"
OUT="/tmp/clutch-srcds-foreground-$$.log"

cd "${SERVER_ROOT}"

echo "=== srcds foreground test (25s max) ==="
echo "dir: $(pwd)"
echo "log: ${OUT}"
echo ""

if [[ ! -x ./srcds_run ]]; then
  echo "ERROR: ./srcds_run missing" >&2
  exit 1
fi

if [[ -f ./bin/srcds_linux ]]; then
  echo "--- ldd bin/srcds_linux (first missing libs) ---"
  ldd ./bin/srcds_linux 2>&1 | grep -i 'not found' || echo "(all linked libs found)"
  echo ""
fi

if [[ -f ./csgo/steam_appid.txt ]]; then
  echo "steam_appid.txt: $(cat ./csgo/steam_appid.txt)"
fi

# Detect CS2 install (srcds_run won't work — need cs2.sh)
if [[ -f ./game/bin/linuxsteamrt64/cs2 ]] || [[ -f ./game/csgo/bin/linuxsteamrt64/cs2 ]]; then
  echo ""
  echo "WARN: This tree looks like CS2 (cs2 binary present)."
  echo "      Classic ./srcds_run -game csgo may crash. Use CS2 cs2.sh or install legacy CSGO ds (app 740)."
  echo ""
fi

ARGS=(
  -tickrate 128
  -game csgo
  -console
  -usercon
  -port "${PORT}"
  +game_type 0
  +game_mode 1
  +map "${MAP}"
  +rcon_password "${RCON}"
  -maxplayers 10
)
if [[ -n "${GSLT}" ]]; then
  ARGS+=(+sv_setsteamaccount "${GSLT}")
fi

echo "Running: ./srcds_run ${ARGS[*]}"
echo "--- output ---"

set +e
timeout 25s ./srcds_run "${ARGS[@]}" 2>&1 | tee "${OUT}"
exit_code="${PIPESTATUS[0]}"
set -e

echo ""
echo "--- exit code: ${exit_code} (124 = timeout = server stayed up 25s) ---"

if [[ "${exit_code}" -eq 124 ]]; then
  echo "OK: srcds ran 25s without dying — screen issue may be separate."
  pkill -u "$(id -u)" -f srcds_linux 2>/dev/null || true
else
  echo "FAIL: srcds exited early. Last lines:"
  tail -25 "${OUT}"
  echo ""
  echo "Common fixes:"
  echo "  1) steamcmd validate: app_update 740 validate"
  echo "  2) libs: apt install lib32gcc-s1 lib32stdc++6 libc6-i386"
  echo "  3) new GSLT in Steam Game Server Account Management"
  echo "  4) full log: ${OUT}"
fi
