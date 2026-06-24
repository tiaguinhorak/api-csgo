#!/usr/bin/env bash
# Diagnóstico RCON: A2S (UDP) pode funcionar mesmo sem TCP RCON (-usercon).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

PORT="${CSGO_RCON_PORT:-27015}"
RCON="${CSGO_RCON_PASSWORD:-clutchclube}"
HOST="${CSGO_SERVER_HOST:-127.0.0.1}"

echo "=== Clutch — diagnose RCON ==="
echo "PORT=${PORT}  RCON_HOST=${HOST}  (TCP game port = RCON when -usercon)"
echo ""

echo "--- 1) srcds command line (must include -usercon) ---"
if pgrep -af srcds_linux >/dev/null 2>&1; then
  pgrep -af srcds_linux | head -3
  if pgrep -af srcds_linux | grep -q -- '-usercon'; then
    echo "OK: -usercon present"
  else
    echo "FAIL: srcds running WITHOUT -usercon — RCON TCP will not work"
    echo "Fix: cd ~/api-csgo && bash scripts/start-csgo-screen.sh"
  fi
else
  echo "FAIL: srcds_linux not running"
fi
echo ""

echo "--- 2) UDP ${PORT} (A2S / game) ---"
ss -uln | grep -E ":${PORT}\\s" || echo "FAIL: no UDP listener"
echo ""

echo "--- 3) TCP ${PORT} (RCON — required) ---"
TCP_LINES="$(ss -tlnp 2>/dev/null | grep -E ":${PORT}\\s" || true)"
if [[ -n "${TCP_LINES}" ]]; then
  echo "${TCP_LINES}"
  if echo "${TCP_LINES}" | grep -q '127.0.0.1'; then
    if ! echo "${TCP_LINES}" | grep -qE '0\\.0\\.0\\.0|\\*'; then
      echo "WARN: TCP may be bound only to 127.0.0.1 — LAN/PC externo não conecta RCON"
      echo "Fix: restart with -ip 0.0.0.0 (start-csgo-screen.sh atualizado)"
    fi
  fi
else
  echo "FAIL: no TCP listener on ${PORT} — admin/site RCON = ECONNREFUSED"
  echo "Fix: restart srcds with -usercon: bash scripts/start-csgo-screen.sh"
fi
echo ""

echo "--- 4) Local RCON test (${HOST}:${PORT}) ---"
if command -v node >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/node_modules/srcds-rcon/package.json" ]]; then
  node -e "
const createRcon = require('srcds-rcon');
const host = process.argv[1];
const port = process.argv[2];
const pass = process.argv[3];
const r = createRcon({ address: host + ':' + port, password: pass });
r.connect()
  .then(() => r.command('status'))
  .then((out) => { console.log('OK:', (out || '').split('\n').slice(0,2).join(' | ')); return r.disconnect(); })
  .catch((e) => { console.log('FAIL:', e.message || e); process.exit(1); });
" "${HOST}" "${PORT}" "${RCON}" 2>/dev/null || echo "Skip node test (run: cd api-csgo && npm install)"
elif command -v nc >/dev/null 2>&1; then
  if nc -z -w2 "${HOST}" "${PORT}" 2>/dev/null; then
    echo "TCP connect OK (nc) — use node/srcds-rcon for auth test"
  else
    echo "FAIL: nc cannot open TCP ${HOST}:${PORT}"
  fi
else
  echo "Install nc or run from api-csgo with node_modules for full test"
fi
echo ""

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "--- 5) From your PC (Windows) ---"
echo "  Test-NetConnection -ComputerName ${LAN_IP:-192.168.100.5} -Port ${PORT}"
echo "  TcpTestSucceeded must be True for RCON from admin panel"
echo ""
