#!/usr/bin/env bash
# Verifica se o warmup está acessível FORA da LAN (jogadores + site Hostinger).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PORT_GAME="${CSGO_RCON_PORT:-27015}"
API_PORT="${PORT:-3001}"
BIND_GAME="${CSGO_BIND_IP:-0.0.0.0}"
PUBLIC_HOST="${CSGO_PUBLIC_HOST:-}"
LAN_HOST="${CSGO_SERVER_HOST:-127.0.0.1}"
REGISTER_HOST="${PUBLIC_HOST:-${LAN_HOST}}"

is_private_ip() {
  local ip="$1"
  [[ "${ip}" == 127.* ]] && return 0
  [[ "${ip}" == 10.* ]] && return 0
  [[ "${ip}" == 192.168.* ]] && return 0
  [[ "${ip}" == 172.16.* || "${ip}" == 172.17.* || "${ip}" == 172.18.* || "${ip}" == 172.19.* ]] && return 0
  [[ "${ip}" == 172.2*.* || "${ip}" == 172.30.* || "${ip}" == 172.31.* ]] && return 0
  return 1
}

detect_public_ipv4() {
  curl -sf --max-time 5 -4 ifconfig.me 2>/dev/null || \
    curl -sf --max-time 5 -4 icanhazip.com 2>/dev/null || \
    curl -sf --max-time 5 -4 api.ipify.org 2>/dev/null || \
    echo ""
}

detect_public_ipv6() {
  curl -sf --max-time 5 -6 ifconfig.me 2>/dev/null || echo ""
}

echo "=== Clutch — warmup public access check ==="
echo "Game UDP/TCP port: ${PORT_GAME}  |  api-csgo TCP: ${API_PORT}"
echo "CSGO_BIND_IP=${BIND_GAME}"
echo "CSGO_SERVER_HOST (RCON/local)=${LAN_HOST}"
echo "CSGO_PUBLIC_HOST (players)=${PUBLIC_HOST:-<not set — using CSGO_SERVER_HOST>}"
echo "Register/push host would be: ${REGISTER_HOST}"
echo ""

if is_private_ip "${REGISTER_HOST}"; then
  echo "FAIL: connect host is PRIVATE (${REGISTER_HOST})"
  echo "  Players outside your LAN cannot connect to 192.168.x / 127.0.0.1"
  echo "  Fix on THIS machine .env:"
  echo "    CSGO_PUBLIC_HOST=<your public IP>"
  echo "    CSGO_SERVER_HOST=127.0.0.1   # RCON local OK"
  echo "  Then: bash scripts/register-local-server.sh"
  echo "  And update Admin → Infra host to the same public IP."
else
  echo "OK: register host looks public (${REGISTER_HOST})"
fi

DETECTED_V4="$(detect_public_ipv4)"
DETECTED_V6="$(detect_public_ipv6)"
if [[ -n "${DETECTED_V4}" ]]; then
  echo ""
  echo "Detected public IPv4: ${DETECTED_V4}"
  if [[ -n "${PUBLIC_HOST}" && "${PUBLIC_HOST}" != "${DETECTED_V4}" ]]; then
    echo "WARN: CSGO_PUBLIC_HOST (${PUBLIC_HOST}) != detected IPv4 (${DETECTED_V4})"
  fi
  if is_private_ip "${REGISTER_HOST}"; then
    echo "  Suggested: CSGO_PUBLIC_HOST=${DETECTED_V4}"
  fi
fi
if [[ -n "${DETECTED_V6}" ]]; then
  echo "Detected public IPv6: ${DETECTED_V6}"
  echo "  (CS:GO connect usually needs IPv4 — set CSGO_PUBLIC_HOST to your IPv4, not IPv6)"
fi
if [[ -z "${DETECTED_V4}" && -z "${DETECTED_V6}" ]]; then
  echo ""
  echo "Could not detect public IP — set CSGO_PUBLIC_HOST manually in .env"
fi

echo ""
echo "--- srcds / UDP ${PORT_GAME} ---"
if pgrep -af srcds_linux >/dev/null 2>&1; then
  echo "OK: srcds_linux running"
else
  echo "FAIL: srcds not running — bash scripts/start-csgo-screen.sh"
fi
if ss -uln 2>/dev/null | grep -qE ":${PORT_GAME}\\s"; then
  echo "OK: UDP ${PORT_GAME} listening"
  ss -uln | grep -E ":${PORT_GAME}\\s" || true
else
  echo "FAIL: no UDP listener on ${PORT_GAME}"
fi
if [[ "${BIND_GAME}" == "127.0.0.1" ]]; then
  echo "FAIL: CSGO_BIND_IP=127.0.0.1 — only accepts local connections"
  echo "  Fix: CSGO_BIND_IP=0.0.0.0 in .env"
fi

echo ""
echo "--- api-csgo TCP ${API_PORT} (site push) ---"
BIND_API="${BIND_HOST:-0.0.0.0}"
echo "BIND_HOST=${BIND_API}"
if ss -tln 2>/dev/null | grep -qE ":${API_PORT}\\s"; then
  ss -tln | grep -E ":${API_PORT}\\s" || true
else
  echo "WARN: nothing listening on TCP ${API_PORT} (pm2 api-csgo?)"
fi
if [[ "${BIND_API}" == "127.0.0.1" ]]; then
  echo "FAIL: BIND_HOST=127.0.0.1 — site cannot push skins from Hostinger"
  echo "  Fix: BIND_HOST=0.0.0.0 && pm2 restart api-csgo --update-env"
fi

echo ""
echo "--- firewall (ufw) ---"
if command -v ufw >/dev/null 2>&1; then
  sudo -n ufw status 2>/dev/null | head -20 || ufw status 2>/dev/null | head -20 || echo "(run: sudo ufw status)"
  if sudo -n ufw status 2>/dev/null | grep -qi active; then
    if ! sudo -n ufw status 2>/dev/null | grep -q "${PORT_GAME}"; then
      echo "WARN: ufw active but no rule for game port ${PORT_GAME}"
      echo "  Run: bash scripts/open-warmup-game-firewall.sh"
    fi
    if ! sudo -n ufw status 2>/dev/null | grep -q "${API_PORT}"; then
      echo "WARN: ufw active but no rule for api port ${API_PORT}"
      echo "  LAN only: bash scripts/open-warmup-api-firewall.sh"
      echo "  Internet: WARMUP_API_PUBLIC=1 bash scripts/open-warmup-api-firewall.sh"
    fi
  fi
else
  echo "(ufw not installed — check cloud provider firewall / router)"
fi

echo ""
echo "--- api-csgo registry (host players see on site) ---"
AUTH_KEY="${API_KEY:-${CSGO_API_KEY:-${CSGO_SKINS_SYNC_KEY:-}}}"
if [[ -n "${AUTH_KEY}" ]]; then
  LIST="$(curl -sf "http://127.0.0.1:${API_PORT}/api/servers" -H "x-api-key: ${AUTH_KEY}" 2>/dev/null || true)"
  if [[ -n "${LIST}" ]]; then
    echo "${LIST}" | node -e "
      let d=''; try { d=JSON.parse(require('fs').readFileSync(0,'utf8')); } catch { process.exit(0); }
      if (!Array.isArray(d)) d=[d];
      for (const s of d) {
        const pool=s.pool||'public';
        console.log('  '+pool+' '+s.name+': '+s.host+':'+s.port+' status='+s.status);
      }
    " 2>/dev/null || echo "${LIST}" | head -c 400
  else
    echo "(could not list /api/servers — is api-csgo running?)"
  fi
else
  echo "(skip — no API_KEY in .env)"
fi

echo ""
echo "=== Site (Hostinger) site/.env ==="
echo "CSGO_WARMUP_API_URL must use PUBLIC IPv4 (not 192.168.x):"
echo "  CSGO_WARMUP_API_URL=http://${DETECTED_V4:-YOUR_PUBLIC_IPV4}:${API_PORT}"
echo "Or CSGO_API_URLS=ranked-ip:3001,warmup-public-ip:3001"
echo ""
echo "Player connect (from outside LAN):"
CONNECT_HOST="${PUBLIC_HOST}"
if [[ -z "${CONNECT_HOST}" ]] || is_private_ip "${CONNECT_HOST}"; then
  CONNECT_HOST="${DETECTED_V4:-YOUR_PUBLIC_IPV4}"
fi
echo "  connect ${CONNECT_HOST}:${PORT_GAME}"
echo ""
echo "From YOUR PC (not on LAN) test UDP:"
echo "  Test-NetConnection -ComputerName ${CONNECT_HOST} -Port ${PORT_GAME}"
echo "  (UDP may show TcpTestSucceeded=False — use in-game connect or A2S query)"
