#!/usr/bin/env bash
# Diagnóstico: por que clientes não conectam ao warmup/ranked CS:GO legacy.
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
CSGO_ROOT="${SERVER_ROOT}/csgo"

echo "=== Clutch — diagnose client connect ==="
echo "SERVER=${SERVER_ROOT}  PORT=${PORT} (UDP)"
echo ""

echo "--- 1) srcds process ---"
pgrep -af srcds_linux || echo "FAIL: srcds_linux not running"
echo ""

echo "--- 2) UDP port ---"
ss -uln | grep -E ":${PORT}\\s" || echo "FAIL: nothing listening on UDP ${PORT}"
echo ""

echo "--- 2b) TCP port (RCON needs -usercon + TCP listener) ---"
ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || echo "FAIL: nothing listening on TCP ${PORT} — RCON from admin/site will fail"
echo "Full RCON check: bash scripts/diagnose-rcon.sh"
echo ""

echo "--- 3) steam_appid.txt (must be 730 for CS:GO) ---"
if [[ -f "${CSGO_ROOT}/steam_appid.txt" ]]; then
  echo "csgo/steam_appid.txt: $(cat "${CSGO_ROOT}/steam_appid.txt")"
else
  echo "MISSING: ${CSGO_ROOT}/steam_appid.txt"
  echo "Fix: bash scripts/ensure-csgo-steam-appid.sh && restart srcds"
fi
echo ""

echo "--- 4) Server type ---"
if [[ -f "${SERVER_ROOT}/bin/srcds_linux" ]] || [[ -f "${SERVER_ROOT}/srcds_linux" ]]; then
  file "$(
    [[ -f "${SERVER_ROOT}/bin/srcds_linux" ]] && echo "${SERVER_ROOT}/bin/srcds_linux" || echo "${SERVER_ROOT}/srcds_linux"
  )" 2>/dev/null || true
  echo "=> CS:GO LEGACY dedicated (app 740). CS2 default client usually CANNOT join."
else
  echo "WARN: no srcds_linux — incomplete install?"
fi
if [[ -f "${SERVER_ROOT}/game/bin/linuxsteamrt64/cs2" ]]; then
  echo "WARN: CS2 binary present — mixed install?"
fi
echo ""

echo "--- 5) LAN IP (use this in connect, not your PC IP) ---"
hostname -I 2>/dev/null | awk '{print $1}' || true
echo "Client command: connect <SERVER_IP>:${PORT}"
echo ""

echo "--- 6) Platform gate (kick after join?) ---"
if [[ -f "${CSGO_ROOT}/addons/sourcemod/plugins/clutch_platform_gate.smx" ]]; then
  echo "clutch_platform_gate installed — unregistered Steam gets kicked"
  echo "Test: sm_cvar clutch_platform_gate_enabled 0  (server console)"
else
  echo "(clutch_platform_gate.smx not in plugins/)"
fi
if [[ -f "${CSGO_ROOT}/addons/sourcemod/extensions/csgo_steamfix.ext.so" ]]; then
  echo "csgo_steamfix: OK (archived CS:GO app 4465480 clients)"
else
  echo "MISSING: csgo_steamfix.ext.so — ticket for wrong game / STEAM validation rejected"
  echo "         run: bash scripts/install-csgo-steamfix-engine.sh"
fi
echo ""

echo "=== CLIENT (your PC) — required for legacy srcds ==="
echo "1) Steam → Counter-Strike 2 → Properties → Betas → csgo_legacy"
echo "   (or install standalone 'CS:GO Legacy' if available)"
echo "2) Launch THAT build, open console (~), run:"
echo "   connect $(hostname -I 2>/dev/null | awk '{print $1}'):${PORT}"
echo ""
echo "If STEAM validation rejected / ticket for wrong game:"
echo "  bash scripts/install-csgo-steamfix-engine.sh  (CS:GO Global archived app 4465480)"
echo "If lobby id ffffffffffffffff:"
echo "  bash scripts/install-nolobby-reservation.sh"
echo ""
echo "From your PC test UDP reachability:"
echo "  ping $(hostname -I 2>/dev/null | awk '{print $1}')"
echo "  (Windows) Test-NetConnection -ComputerName IP -Port ${PORT}"
