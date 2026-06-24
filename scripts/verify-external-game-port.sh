#!/usr/bin/env bash
# Diagnóstico: servidor OK localmente mas jogadores de fora não conectam (roteador / CGNAT).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

GAME_PORT="${CSGO_RCON_PORT:-27015}"
PUBLIC="${CSGO_PUBLIC_HOST:-}"
API_PORT="${PORT:-3001}"

detect_ipv4() {
  curl -sf --max-time 5 -4 ifconfig.me 2>/dev/null || echo ""
}

echo "=== Clutch — external connect (router / CGNAT) ==="
echo ""

LAN_IPS="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)"
DETECTED="$(detect_ipv4)"

echo "Game port: UDP/TCP ${GAME_PORT}"
echo "API port: TCP ${API_PORT}"
echo "CSGO_PUBLIC_HOST=${PUBLIC:-<not set>}"
echo "LAN IPs on this machine:"
echo "${LAN_IPS}" | sed 's/^/  /'
echo "Outbound public IPv4 (curl -4): ${DETECTED}"
echo ""

NEEDS_FORWARD=0
while IFS= read -r lip; do
  [[ -z "${lip}" ]] && continue
  if [[ "${lip}" == 192.168.* || "${lip}" == 10.* || "${lip}" == 172.16.* || "${lip}" == 172.17.* \
    || "${lip}" == 172.18.* || "${lip}" == 172.19.* || "${lip}" == 172.2*.* \
    || "${lip}" == 172.30.* || "${lip}" == 172.31.* ]]; then
    NEEDS_FORWARD=1
  fi
done <<< "${LAN_IPS}"

if [[ "${NEEDS_FORWARD}" -eq 1 ]]; then
  echo ">>> ROTEADOR OBRIGATÓRIO"
  echo "Este PC usa IP privado na LAN. O ufw no Linux NÃO basta."
  echo "No roteador/modem, crie PORT FORWARD:"
  echo "  Protocolo: UDP (e opcional TCP para RCON)"
  echo "  Porta externa: ${GAME_PORT}"
  echo "  IP interno destino: $(echo "${LAN_IPS}" | awk '{print $1}')"
  echo "  Porta interna: ${GAME_PORT}"
  echo ""
  echo "Teste de FORA da sua Wi‑Fi (4G no celular): connect ${PUBLIC:-${DETECTED}}:${GAME_PORT}"
  echo "Na mesma rede, connect pelo IP público costuma FALHAR (hairpin NAT)."
else
  echo "Machine may have direct public IP — ufw rules should be enough."
fi

echo ""
echo "--- srcds listening? ---"
if ss -uln 2>/dev/null | grep -qE ":${GAME_PORT}\\s"; then
  ss -uln | grep -E ":${GAME_PORT}\\s" || true
else
  echo "FAIL: no UDP listener on ${GAME_PORT}"
fi

echo ""
echo "--- api /health (site push) ---"
if curl -sf --max-time 3 "http://127.0.0.1:${API_PORT}/health" >/dev/null; then
  echo "OK: http://127.0.0.1:${API_PORT}/health"
else
  echo "WARN: api-csgo not responding on :${API_PORT}"
fi

AUTH_KEY="${API_KEY:-${CSGO_API_KEY:-${CSGO_SKINS_SYNC_KEY:-}}}"
if [[ -n "${AUTH_KEY}" ]]; then
  echo ""
  echo "--- registry (key from .env — not SUACHAVE) ---"
  curl -sf "http://127.0.0.1:${API_PORT}/api/servers" -H "x-api-key: ${AUTH_KEY}" | node -e "
    let d=[]; try{d=JSON.parse(require('fs').readFileSync(0,'utf8'))}catch{}
    for (const s of d) console.log('  '+s.pool+' '+s.name+': '+s.host+':'+s.port+' status='+s.status);
  " 2>/dev/null || echo "(list failed)"
fi

echo ""
echo "=== Teste de porta ABERTA na internet (de outra rede) ==="
echo "1) Celular em 4G (sem Wi‑Fi): https://www.yougetsignal.com/tools/open-ports/"
echo "   Remote Address: ${PUBLIC:-${DETECTED}}  Port: ${GAME_PORT}"
echo "   UDP não aparece nesse site — use connect no jogo."
echo ""
echo "2) CS:GO Legacy (beta csgo_legacy), console:"
echo "   connect ${PUBLIC:-${DETECTED}}:${GAME_PORT}"
echo ""
echo "3) Se porta fechada de fora mas ufw OK → port forward no roteador ou CGNAT da operadora."
echo ""
echo "4) Site Hostinger .env:"
echo "   CSGO_WARMUP_API_URL=http://${PUBLIC:-${DETECTED}}:${API_PORT}"
echo ""
echo "5) Kick após entrar? No console do servidor:"
echo "   sm_cvar clutch_platform_gate_enabled 0"
