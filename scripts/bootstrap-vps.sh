#!/usr/bin/env bash
# Bootstrap completo da VPS: OS deps, Node, SteamCMD, CS:GO, SourceMod, runtime libs.
# Chamado por ./install.sh — idempotente (só instala o que falta).
#
# Uso:
#   bash scripts/bootstrap-vps.sh
#   bash scripts/bootstrap-vps.sh --skip-os --skip-csgo
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

SKIP_OS=0
SKIP_CSGO=0
SKIP_STEAMCMD=0
SKIP_SOURCEMOD=0

for arg in "$@"; do
  case "${arg}" in
    --skip-os) SKIP_OS=1 ;;
    --skip-csgo) SKIP_CSGO=1 ;;
    --skip-steamcmd) SKIP_STEAMCMD=1 ;;
    --skip-sourcemod) SKIP_SOURCEMOD=1 ;;
    -h|--help)
      cat <<'EOF'
Bootstrap VPS Clutch (pré-requisitos + CS:GO + SourceMod)

  bash scripts/bootstrap-vps.sh

Opções:
  --skip-os          não roda apt (libs 32-bit, git, screen, etc.)
  --skip-steamcmd    não instala SteamCMD
  --skip-csgo        não baixa app 740
  --skip-sourcemod   não instala MetaMod/SourceMod
EOF
      exit 0
    ;;
    *)
      echo "Opção desconhecida: ${arg}" >&2
      exit 1
    ;;
  esac
done

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

export CSGO_SERVER_DIR="${CSGO_SERVER_DIR:-${HOME}/server}"
export STEAMCMD_DIR="${STEAMCMD_DIR:-${HOME}/steamcmd}"
export STEAMCMD="${STEAMCMD:-${STEAMCMD_DIR}/steamcmd.sh}"
CSGO_ROOT="${CSGO_SERVER_DIR}/csgo"

echo "=========================================="
echo "  Clutch — bootstrap VPS"
echo "=========================================="
echo "User: $(whoami) | CSGO_SERVER_DIR=${CSGO_SERVER_DIR}"
echo "SteamCMD: ${STEAMCMD}"

if [[ "${SKIP_OS}" -eq 0 ]]; then
  if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    echo ""
    echo ">>> Pacotes base (apt)"
    sudo apt-get update -qq
    sudo apt-get install -y \
      git curl wget screen file ca-certificates gnupg \
      build-essential libcurl4-gnutls-dev 2>/dev/null || \
      sudo apt-get install -y git curl wget screen file ca-certificates build-essential

    echo ""
    echo ">>> Libs 32-bit para srcds"
    bash "${REPO_ROOT}/scripts/install-csgo-runtime-libs.sh" || true
  else
    echo "WARN: apt/sudo indisponível — pulando pacotes OS (instale git curl wget screen manualmente)"
  fi
fi

echo ""
echo ">>> Node.js"
bash "${REPO_ROOT}/scripts/install-node.sh"

if [[ "${SKIP_STEAMCMD}" -eq 0 ]]; then
  echo ""
  bash "${REPO_ROOT}/scripts/install-steamcmd.sh"
fi

if [[ "${SKIP_CSGO}" -eq 0 ]]; then
  echo ""
  bash "${REPO_ROOT}/scripts/install-csgo-server.sh"
fi

if [[ "${SKIP_SOURCEMOD}" -eq 0 ]]; then
  if [[ ! -d "${CSGO_ROOT}/addons/sourcemod" ]]; then
    echo ""
    echo ">>> MetaMod + SourceMod"
    bash "${REPO_ROOT}/scripts/install-sourcemod-metamod.sh"
  else
    echo ""
    echo "OK: SourceMod já em ${CSGO_ROOT}/addons/sourcemod"
  fi
fi

echo ""
echo "=========================================="
echo "  Bootstrap concluído"
echo "=========================================="
echo "Próximo: edite .env e rode ./deploy.sh (ou continue install.sh)"
