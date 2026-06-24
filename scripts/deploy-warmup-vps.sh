#!/usr/bin/env bash
set -euo pipefail

# Deploy completo na VPS WARMUP — paridade com ranked (api-csgo + sync + plugins).
#
# Uso (usuário csgo na warmup VPS):
#   cd ~/api-csgo && bash scripts/deploy-warmup-vps.sh
#
# Requer no .env:
#   WARMUP_VPS=1
#   CLUTCH_CS_SCREEN=csgo-warmup-#1
#   CSGO_SKINS_SYNC_KEY, CLUTCH_SITE_URL, RCON vars (igual ranked)
#
# No site (.env):
#   CSGO_WARMUP_API_URL=http://<warmup-ip>:3001

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
Clutch deploy warmup VPS (paridade com ranked)

  bash scripts/deploy-warmup-vps.sh

Opções:
  --skip-pull      não faz git pull
  --skip-ingame    não recarrega plugins no screen (CS offline)
  --skip-plugin    só API (build + pm2 + syncs), sem plugins SourceMod
EOF
      exit 0
    ;;
    *)
      echo "Opção desconhecida: ${arg}" >&2
      exit 1
    ;;
  esac
done

export WARMUP_VPS=1

chmod +x "${REPO_ROOT}/deploy.sh" "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

echo "=========================================="
echo "  Clutch — deploy WARMUP VPS"
echo "=========================================="
echo "Repo: ${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ "${WARMUP_VPS:-}" != "1" ]]; then
  echo "WARN: WARMUP_VPS=1 not set in .env — adding for this run"
  export WARMUP_VPS=1
fi

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
echo ">>> warmup .env (api-csgo + site sync)"
bash "${REPO_ROOT}/scripts/ensure-warmup-api-env.sh"

echo ""
echo ">>> npm install"
npm install --no-audit --no-fund

echo ""
echo ">>> npm run build"
npm run build

if ! command -v pm2 >/dev/null 2>&1; then
  echo ""
  echo ">>> installing pm2 (local npm — site push needs api-csgo on warmup)"
  npm install pm2 --no-save --no-audit --no-fund
fi
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/pm2-local.sh"

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "ERROR: build sem gloves sync — verifique erros de compilação" >&2
  exit 1
fi

if command -v pm2 >/dev/null 2>&1; then
  echo ""
  echo ">>> pm2 (api-csgo — warmup recebe player-sync do site)"
  "${REPO_ROOT}/scripts/pm2-ensure-api-csgo.sh"
else
  echo "WARN: pm2 não encontrado — site não pode push direto; use sync-team-loadouts-warmup.sh"
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
    echo "WARN: api-csgo não verificada — sync manual via sync-team-loadouts-warmup.sh"
  fi
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" && -z "${API_KEY:-}" ]]; then
  echo ""
  echo "WARN: sem CSGO_SKINS_SYNC_KEY/API_KEY no .env — push do site retorna 401"
fi

echo ""
echo ">>> warmup extras (nolobby, steamfix, ptah)"
bash "${REPO_ROOT}/scripts/install-nolobby-reservation.sh" || true
bash "${REPO_ROOT}/scripts/install-csgo-steamfix-engine.sh" || true
bash "${REPO_ROOT}/scripts/install-ptah.sh" || true

echo ""
echo ">>> sync allowlist Steam (platform gate)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" && -n "${CLUTCH_SITE_URL:-}" ]]; then
  if ! bash "${REPO_ROOT}/scripts/check-site-dns.sh"; then
    echo "WARN: DNS/site check failed — allowlist sync skipped" >&2
  else
    bash "${REPO_ROOT}/scripts/sync-steam-allowlist.sh" || {
      echo "WARN: sync allowlist falhou" >&2
    }
    bash "${REPO_ROOT}/scripts/verify-steam-allowlist.sh" || true
  fi
else
  echo "Skip (defina CLUTCH_SITE_URL + CSGO_SKINS_SYNC_KEY no .env)"
fi

echo ""
echo ">>> sync loadouts equipados (site → SQLite + stage in-game)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  bash "${REPO_ROOT}/scripts/sync-team-loadouts-from-site.sh" || {
    echo "WARN: sync loadouts falhou" >&2
  }
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> sync weapons_english.cfg (warmup — node, no HTTP)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  bash "${REPO_ROOT}/scripts/sync-weapons-cfg-warmup.sh" || {
    echo "WARN: sync weapons cfg falhou" >&2
  }
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> warmup bridge cfg (defer_live=0)"
bash "${REPO_ROOT}/scripts/ensure-warmup-bridge-cfg.sh" || true

echo ""
echo ">>> branding servidor (motd.txt)"
bash "${REPO_ROOT}/scripts/ensure-clutch-server-branding.sh" || {
  echo "WARN: branding falhou" >&2
}

if [[ "${SKIP_PLUGIN}" -eq 0 ]]; then
  echo ""
  echo ">>> plugins SourceMod — skins bridge + disable kgns gloves"
  bash "${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh" || {
    echo "WARN: install-clutch-skins-bridge falhou" >&2
  }

  echo ""
  echo ">>> plugins SourceMod — warmup extras (sem match tracker)"
  bash "${REPO_ROOT}/scripts/install-warmup-plugins.sh" || {
    echo "WARN: install-warmup-plugins falhou" >&2
  }

  echo ""
  echo ">>> plugins SourceMod — stickers (opcional, paridade ranked)"
  if [[ -f "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" ]]; then
    bash "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" || {
      echo "WARN: install-csgo-weaponstickers falhou" >&2
    }
  fi
fi

echo ""
echo "=== Health check ==="
sleep 1
curl -sf "http://127.0.0.1:${PORT:-3001}/health" && echo "" || \
  echo "WARN: api-csgo não responde em :${PORT:-3001}"

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
  if bash "${REPO_ROOT}/scripts/reload-clutch-skins-ingame.sh"; then
    echo "Reload in-game OK."
  else
    echo "WARN: reload in-game falhou (CS offline?). Quando subir: bash scripts/reload-clutch-skins-ingame.sh"
  fi
fi

echo ""
echo "=========================================="
echo "  Deploy warmup concluído"
echo "=========================================="
echo "Bridge: ${BRIDGE_VER} | Gate: ${GATE_VER}"
echo "Site: CSGO_WARMUP_API_URL=http://<this-vps-ip>:${PORT:-3001}"
echo "Screen: sm plugins info z_clutch_skins_bridge"
echo "Após editar .env: pm2 restart api-csgo --update-env"
