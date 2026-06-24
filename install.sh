#!/usr/bin/env bash
# Instalação 100% Clutch VPS — um comando:
#   git clone ... && cd api-csgo && ./install.sh
#
# Faz: apt libs, Node, SteamCMD, CS:GO app 740, SourceMod, npm build, pm2, plugins, skins sync.
# Não usa Docker — CS:GO Legacy + SourceMod rodam melhor no host.
#
# Opções:
#   ./install.sh --skip-bootstrap     só deploy (CS:GO já instalado)
#   ./install.sh --skip-os            não roda apt
#   ./install.sh --skip-csgo          não baixa CS:GO
#   ./install.sh --start-game         inicia srcds em screen após deploy
#   ./install.sh --skip-ingame        deploy sem reload RCON
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

SKIP_BOOTSTRAP=0
SKIP_OS=0
SKIP_CSGO=0
START_GAME=0
DEPLOY_ARGS=()

for arg in "$@"; do
  case "${arg}" in
    --skip-bootstrap) SKIP_BOOTSTRAP=1 ;;
    --skip-os) SKIP_OS=1 ;;
    --skip-csgo) SKIP_CSGO=1 ;;
    --start-game) START_GAME=1 ;;
    --skip-ingame|--skip-pull|--skip-plugin|--profile=*)
      DEPLOY_ARGS+=("${arg}")
    ;;
    -h|--help)
      cat <<'EOF'
Clutch — instalação completa VPS (um script)

  ./install.sh

Fluxo:
  1. bootstrap: apt, Node 20, SteamCMD, CS:GO (740), SourceMod
  2. .env (copia .env.example se não existe)
  3. deploy: npm, pm2, api-csgo, plugins, skins, allowlist

Antes de rodar, edite .env (ou depois do primeiro cp):
  SERVER_PROFILE, CSGO_SKINS_SYNC_KEY, CLUTCH_SITE_URL,
  CSGO_RCON_PASSWORD, CSGO_GSLT_TOKEN, CLUTCH_CS_SCREEN

Opções:
  --skip-bootstrap   pula SteamCMD/CS:GO/SourceMod
  --skip-os          pula apt
  --skip-csgo        pula download CS:GO
  --start-game       inicia srcds (screen) no final
  --skip-ingame      igual deploy.sh
  --profile=NAME     perfil só nesta execução

Docker: não suportado neste repo — use este script no Ubuntu bare metal.
EOF
      exit 0
    ;;
    *)
      echo "Opção desconhecida: ${arg} (use --help)" >&2
      exit 1
    ;;
  esac
done

echo "=========================================="
echo "  Clutch — instalação VPS (completa)"
echo "=========================================="

if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    echo "Created .env from .env.example"
  else
    echo "ERROR: .env.example missing" >&2
    exit 1
  fi
fi

echo ""
echo ">>> Edite .env se necessário:"
echo "    SERVER_PROFILE=ranked|warmup|deathmatch|surf|..."
echo "    CSGO_SKINS_SYNC_KEY (igual ao site)"
echo "    CLUTCH_SITE_URL, CSGO_RCON_PASSWORD, CSGO_GSLT_TOKEN"
echo "    CLUTCH_CS_SCREEN, SERVER_NAME, CSGO_SERVER_DIR"
echo ""

chmod +x "${REPO_ROOT}/deploy.sh" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

if [[ "${SKIP_BOOTSTRAP}" -eq 0 ]]; then
  BOOT_ARGS=()
  if [[ "${SKIP_OS}" -eq 1 ]]; then BOOT_ARGS+=(--skip-os); fi
  if [[ "${SKIP_CSGO}" -eq 1 ]]; then BOOT_ARGS+=(--skip-csgo); fi
  bash "${REPO_ROOT}/scripts/bootstrap-vps.sh" "${BOOT_ARGS[@]}"
else
  if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: Node.js 18+ required" >&2
    exit 1
  fi
  echo "Node: $(node -v)"
fi

bash "${REPO_ROOT}/scripts/ensure-profile-env.sh"

echo ""
echo ">>> Running unified deploy..."
bash "${REPO_ROOT}/scripts/deploy-unified.sh" "${DEPLOY_ARGS[@]}"

if [[ "${START_GAME}" -eq 1 || "${CSGO_AUTO_START:-0}" == "1" ]]; then
  echo ""
  echo ">>> Iniciando CS:GO (screen)"
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
  if [[ -z "${CSGO_GSLT_TOKEN:-}" ]]; then
    echo "WARN: CSGO_GSLT_TOKEN vazio — srcds pode falhar sem GSLT" >&2
  fi
  bash "${REPO_ROOT}/scripts/start-csgo-screen.sh"
fi

echo ""
echo "=========================================="
echo "  Instalação concluída"
echo "=========================================="
echo "API:  pm2 status"
echo "Game: screen -r ${CLUTCH_CS_SCREEN:-csgo-clutch-#1}  (ou bash scripts/start-csgo-screen.sh)"
echo "Site: adicione esta VPS em CSGO_API_URLS / CSGO_WARMUP_API_URL"
