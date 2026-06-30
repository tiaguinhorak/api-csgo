#!/usr/bin/env bash
# Instala Netdata na VPS (monitoramento CPU/RAM/disco/rede/processos).
#
# Uso (como root na VPS):
#   curl -fsSL https://raw.githubusercontent.com/tiaguinhorak/api-csgo/main/scripts/install-netdata.sh | bash
#   # ou, já com o repo:
#   sudo bash scripts/install-netdata.sh
#
# Painel local: http://IP_DA_VPS:19999
# Recomendado: restringir a porta 19999 no firewall ao seu IP admin.
#
set -euo pipefail

NETDATA_CLAIM_TOKEN="${NETDATA_CLAIM_TOKEN:-}"
NETDATA_CLAIM_ROOMS="${NETDATA_CLAIM_ROOMS:-}"
NETDATA_CLAIM_URL="${NETDATA_CLAIM_URL:-https://app.netdata.cloud}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: rode como root (sudo bash $0)" >&2
  exit 1
fi

echo "[netdata] baixando kickstart..."
curl -fsSL https://get.netdata.cloud/kickstart.sh -o /tmp/netdata-kickstart.sh
chmod +x /tmp/netdata-kickstart.sh

CLAIM_ARGS=()
if [[ -n "${NETDATA_CLAIM_TOKEN}" ]]; then
  CLAIM_ARGS+=(--claim-token "${NETDATA_CLAIM_TOKEN}")
  CLAIM_ARGS+=(--claim-url "${NETDATA_CLAIM_URL}")
  if [[ -n "${NETDATA_CLAIM_ROOMS}" ]]; then
    CLAIM_ARGS+=(--claim-rooms "${NETDATA_CLAIM_ROOMS}")
  fi
  echo "[netdata] vinculando ao Netdata Cloud (opcional)..."
fi

echo "[netdata] instalando (pode levar 1–3 min)..."
/tmp/netdata-kickstart.sh --non-interactive "${CLAIM_ARGS[@]}"

PUBLIC_IP="$(curl -fsSL -4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

echo ""
echo "=========================================="
echo " Netdata instalado."
echo " Painel: http://${PUBLIC_IP}:19999"
echo ""
echo " Segurança (ufw exemplo — troque SEU_IP):"
echo "   ufw allow from SEU_IP to any port 19999 proto tcp"
echo "   ufw deny 19999/tcp"
echo ""
echo " Netdata Cloud (opcional): crie em https://app.netdata.cloud"
echo "   export NETDATA_CLAIM_TOKEN=... NETDATA_CLAIM_ROOMS=..."
echo "   sudo -E bash scripts/install-netdata.sh"
echo "=========================================="
