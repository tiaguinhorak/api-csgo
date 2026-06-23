#!/usr/bin/env bash
set -euo pipefail

# Deploy completo na VPS — UM comando para tudo.
#
# Uso (como usuário csgo na VPS):
#   cd ~/api-csgo && ./deploy.sh
#   cd ~/api-csgo && ./scripts/deploy-vps.sh
#
# Fluxo:
#   git pull → npm build → pm2 → sync allowlist Steam → sync weapons cfg →
#   branding motd → instalar TODOS os plugins Clutch + stickers → reload in-game
#
# Opções:
#   --skip-pull          não roda git pull
#   --skip-ingame        não recarrega plugins no screen do CS
#   --skip-plugin        só API (npm build + pm2 + sync), sem compilar plugins

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

SKIP_PULL=0
SKIP_INGAME=0
SKIP_PLUGIN=0

for arg in "$@"; do
  case "${arg}" in
    --skip-pull) SKIP_PULL=1 ;;
    --skip-ingame) SKIP_INGAME=1 ;;
    --skip-plugin) SKIP_PLUGIN=1 ;;
    -h|--help)
      cat <<'EOF'
Clutch deploy completo (VPS)

  ./deploy.sh

Opções:
  --skip-pull      não faz git pull
  --skip-ingame    não recarrega plugins no screen (CS offline)
  --skip-plugin    só API (build + pm2 + syncs), sem plugins SourceMod

Site (Hostinger): git pull + rebuild separado no painel Hostinger.
EOF
      exit 0
    ;;
    *)
      echo "Opção desconhecida: ${arg}" >&2
      exit 1
    ;;
  esac
done

chmod +x "${REPO_ROOT}/deploy.sh" "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

echo "=========================================="
echo "  Clutch — deploy completo (api-csgo + CS)"
echo "=========================================="
echo "Repo: ${REPO_ROOT}"

if [[ "${SKIP_PULL}" -eq 0 && -d .git ]]; then
  echo ""
  echo ">>> git pull"
  git pull --ff-only
fi

if [[ -d .git ]]; then
  echo "Git: $(git rev-parse --short HEAD) ($(git branch --show-current 2>/dev/null || echo '?'))"
fi

BRIDGE_VER="$(grep -E '#define PLUGIN_VERSION' sourcemod/clutch_skins_bridge.sp | sed 's/.*"\(.*\)".*/\1/')"
GATE_VER="$(grep -E '#define PLUGIN_VERSION' sourcemod/clutch_platform_gate.sp | sed 's/.*"\(.*\)".*/\1/')"
echo "Plugin bridge: ${BRIDGE_VER} | platform gate: ${GATE_VER}"

if [[ ! -f package.json ]]; then
  echo "ERROR: não é o repo api-csgo" >&2
  exit 1
fi

echo ""
echo ">>> npm install"
npm install --no-audit --no-fund

echo ""
echo ">>> npm run build"
npm run build

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "ERROR: build sem gloves sync — verifique erros de compilação" >&2
  exit 1
fi

if command -v pm2 >/dev/null 2>&1; then
  echo ""
  echo ">>> pm2 (api-csgo)"
  "${REPO_ROOT}/scripts/pm2-ensure-api-csgo.sh"
else
  echo "WARN: pm2 não encontrado — reinicie api-csgo manualmente"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

echo ""
echo ">>> verificar API em execução"
if ! "${REPO_ROOT}/scripts/verify-api-running-build.sh"; then
  if command -v pm2 >/dev/null 2>&1; then
    echo ""
    echo ">>> processo antigo — pm2-recover"
    "${REPO_ROOT}/scripts/pm2-recover.sh"
    sleep 2
    "${REPO_ROOT}/scripts/verify-api-running-build.sh"
  else
    exit 1
  fi
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" && -z "${API_KEY:-}" ]]; then
  echo ""
  echo "WARN: sem CSGO_SKINS_SYNC_KEY/API_KEY no .env — push do site pode retornar 401"
fi

echo ""
echo ">>> sync allowlist Steam (platform gate)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" && -n "${CLUTCH_SITE_URL:-}" ]]; then
  if ! bash "${REPO_ROOT}/scripts/check-site-dns.sh"; then
    echo "WARN: DNS/site check failed — allowlist sync skipped" >&2
  else
    bash "${REPO_ROOT}/scripts/sync-steam-allowlist.sh" || {
      echo "WARN: sync allowlist falhou — verifique CLUTCH_SITE_URL e site deploy" >&2
    }
    bash "${REPO_ROOT}/scripts/verify-steam-allowlist.sh" || true
  fi
else
  echo "Skip (defina CLUTCH_SITE_URL + CSGO_SKINS_SYNC_KEY no .env)"
fi

echo ""
echo ">>> sync loadouts equipados (site → SQLite)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  curl -sf -X POST "http://127.0.0.1:${PORT:-3000}/api/csgo/skins/sync-from-site" \
    -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    -H "Content-Type: application/json" | head -c 400 || {
    echo "WARN: sync-from-site falhou" >&2
  }
  echo ""
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> sync weapons_english.cfg do catálogo do site"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  bash "${REPO_ROOT}/scripts/sync-weapons-cfg-from-site.sh" || {
    echo "WARN: sync weapons cfg falhou" >&2
  }
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> branding servidor (motd.txt)"
bash "${REPO_ROOT}/scripts/ensure-clutch-server-branding.sh" || {
  echo "WARN: branding falhou" >&2
}

if [[ "${SKIP_PLUGIN}" -eq 0 ]]; then
  echo ""
  echo ">>> plugins SourceMod — skins bridge + gloves"
  "${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh"

  echo ""
  echo ">>> plugins SourceMod — match tracker"
  if [[ -f "${REPO_ROOT}/scripts/install-clutch-match-tracker.sh" ]]; then
    bash "${REPO_ROOT}/scripts/install-clutch-match-tracker.sh" || {
      echo "WARN: install-clutch-match-tracker falhou" >&2
    }
  fi

  echo ""
  echo ">>> plugins SourceMod — platform gate"
  if [[ -f "${REPO_ROOT}/scripts/install-clutch-platform-gate.sh" ]]; then
    bash "${REPO_ROOT}/scripts/install-clutch-platform-gate.sh" || {
      echo "WARN: install-clutch-platform-gate falhou" >&2
    }
  fi

  echo ""
  echo ">>> plugins SourceMod — stickers (eItems + weaponstickers + ripext)"
  if [[ -f "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" ]]; then
    bash "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" || {
      echo "WARN: install-csgo-weaponstickers falhou — rode manualmente se precisar" >&2
    }
  fi
fi

echo ""
echo "=== Health check ==="
sleep 1
curl -sf "http://127.0.0.1:${PORT:-3000}/health" && echo "" || echo "WARN: api-csgo não responde em :${PORT:-3000}"

echo ""
echo "=== Teste gloves sync (opcional) ==="
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  "${REPO_ROOT}/scripts/test-gloves-sync.sh" "STEAM_1:0:203852188" || true
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

if [[ "${SKIP_INGAME}" -eq 0 ]]; then
  echo ""
  echo ">>> reload plugins no screen do CS"
  if "${REPO_ROOT}/scripts/reload-clutch-skins-ingame.sh"; then
    echo "Reload in-game OK."
  else
    echo "WARN: reload in-game falhou (CS offline?). Quando subir: ./scripts/reload-clutch-skins-ingame.sh"
  fi
fi

echo ""
echo "=========================================="
echo "  Deploy concluído"
echo "=========================================="
echo "Bridge: ${BRIDGE_VER} | Gate: ${GATE_VER}"
echo "Screen: sm plugins info z_clutch_skins_bridge"
echo "        sm plugins info clutch_platform_gate"
echo "        sm plugins list | grep -iE 'eitems|weaponstickers'"
echo "Após editar .env: pm2 restart api-csgo --update-env"
echo "Site Hostinger: git pull + rebuild no painel (separado da VPS)"
