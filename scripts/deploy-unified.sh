#!/usr/bin/env bash
set -euo pipefail

# Unified Clutch VPS deploy — one pipeline for ranked, warmup, deathmatch, surf, etc.
# Configure only .env (SERVER_PROFILE + connection vars), then:
#   cd ~/api-csgo && ./install.sh    # first time
#   cd ~/api-csgo && ./deploy.sh     # updates

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  env_repair_unquoted_values "${REPO_ROOT}/.env"
fi

SKIP_PULL=0
SKIP_INGAME=0
SKIP_PLUGIN=0
PROFILE_OVERRIDE=""

for arg in "$@"; do
  case "${arg}" in
    --skip-pull) SKIP_PULL=1 ;;
    --skip-ingame) SKIP_INGAME=1 ;;
    --skip-plugin) SKIP_PLUGIN=1 ;;
    --profile=*) PROFILE_OVERRIDE="${arg#--profile=}" ;;
    -h|--help)
      cat <<'EOF'
Clutch unified deploy (all server types)

  ./deploy.sh
  bash scripts/deploy-unified.sh --profile=deathmatch

Configure .env once:
  SERVER_PROFILE=ranked|warmup|deathmatch|surf|retake|kz|...
  CSGO_SKINS_SYNC_KEY, CLUTCH_SITE_URL, CSGO_RCON_PASSWORD, CLUTCH_CS_SCREEN

Options:
  --profile=NAME   override SERVER_PROFILE for this run
  --skip-pull      no git pull
  --skip-ingame    no screen plugin reload
  --skip-plugin    API only (no SourceMod compile)
EOF
      exit 0
    ;;
    *)
      echo "Opção desconhecida: ${arg}" >&2
      exit 1
    ;;
  esac
done

if [[ -n "${PROFILE_OVERRIDE}" ]]; then
  export SERVER_PROFILE="${PROFILE_OVERRIDE}"
fi

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/profile.sh"
clutch_profile_init "${REPO_ROOT}"

chmod +x "${REPO_ROOT}/deploy.sh" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

echo "=========================================="
echo "  Clutch — deploy unificado"
echo "=========================================="
clutch_profile_banner
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
echo "Plugins: bridge ${BRIDGE_VER} | gate ${GATE_VER}"

if [[ ! -f package.json ]]; then
  echo "ERROR: não é o repo api-csgo" >&2
  exit 1
fi

echo ""
echo ">>> ensure .env (profile)"
bash "${REPO_ROOT}/scripts/ensure-profile-env.sh"
# Re-load after ensure may have appended keys
source_clutch_env "${REPO_ROOT}/.env"
clutch_profile_init "${REPO_ROOT}"

echo ""
echo ">>> npm install"
npm install --no-audit --no-fund

echo ""
echo ">>> npm run build"
npm run build

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "ERROR: build sem gloves sync" >&2
  exit 1
fi

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  if ! command -v pm2 >/dev/null 2>&1; then
    echo ">>> installing pm2 (local)"
    npm install pm2 --no-save --no-audit --no-fund
  fi
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/pm2-local.sh"
fi

if command -v pm2 >/dev/null 2>&1; then
  echo ""
  echo ">>> pm2 (api-csgo)"
  "${REPO_ROOT}/scripts/pm2-ensure-api-csgo.sh"
else
  echo "WARN: pm2 não encontrado"
fi

echo ""
echo ">>> verificar API"
if ! "${REPO_ROOT}/scripts/verify-api-running-build.sh"; then
  if command -v pm2 >/dev/null 2>&1; then
    "${REPO_ROOT}/scripts/pm2-recover.sh"
    sleep 2
    "${REPO_ROOT}/scripts/verify-api-running-build.sh"
  else
    exit 1
  fi
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" && -z "${API_KEY:-}" ]]; then
  echo "WARN: sem CSGO_SKINS_SYNC_KEY/API_KEY — push do site retorna 401"
fi

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  echo ""
  echo ">>> public extras (nolobby, steamfix, ptah)"
  bash "${REPO_ROOT}/scripts/install-nolobby-reservation.sh" || true
  bash "${REPO_ROOT}/scripts/install-csgo-steamfix-engine.sh" || true
  bash "${REPO_ROOT}/scripts/install-ptah.sh" || true
fi

echo ""
echo ">>> sync allowlist Steam"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" && -n "${CLUTCH_SITE_URL:-}" ]]; then
  bash "${REPO_ROOT}/scripts/check-site-dns.sh" || echo "WARN: DNS check failed" >&2
  bash "${REPO_ROOT}/scripts/sync-steam-allowlist.sh" || true
  bash "${REPO_ROOT}/scripts/verify-steam-allowlist.sh" || true
else
  echo "Skip (CLUTCH_SITE_URL + CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> sync loadouts (site → SQLite)"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  if [[ "${CLUTCH_IS_RANKED}" -eq 1 ]]; then
    bash "${REPO_ROOT}/scripts/sync-loadouts-from-site-curl.sh" || true
  else
    bash "${REPO_ROOT}/scripts/sync-team-loadouts-from-site.sh" || true
  fi
else
  echo "Skip (sem CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> sync weapons_english.cfg"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  if [[ "${CLUTCH_IS_RANKED}" -eq 1 ]]; then
    bash "${REPO_ROOT}/scripts/sync-weapons-cfg-from-site.sh" || true
  else
    bash "${REPO_ROOT}/scripts/sync-weapons-cfg-warmup.sh" || true
  fi
fi

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  echo ""
  echo ">>> bridge cfg (instant skins)"
  bash "${REPO_ROOT}/scripts/ensure-warmup-bridge-cfg.sh" || true
fi

echo ""
echo ">>> branding (motd)"
bash "${REPO_ROOT}/scripts/ensure-clutch-server-branding.sh" || true

if [[ "${SKIP_PLUGIN}" -eq 0 ]]; then
  echo ""
  echo ">>> plugins — skins bridge + gloves (global stack)"
  bash "${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh"

  if [[ "${CLUTCH_IS_RANKED}" -eq 1 ]]; then
    echo ""
    echo ">>> plugins — match tracker (ranked only)"
    bash "${REPO_ROOT}/scripts/install-clutch-match-tracker.sh" || true
    bash "${REPO_ROOT}/scripts/install-clutch-platform-gate.sh" || true
  else
    echo ""
    echo ">>> plugins — public stack (gate, no match tracker)"
    bash "${REPO_ROOT}/scripts/install-warmup-plugins.sh" || true
  fi

  echo ""
  echo ">>> plugins — stickers"
  bash "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" || true
fi

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  echo ""
  echo ">>> LAN firewall (site push)"
  bash "${REPO_ROOT}/scripts/open-warmup-api-firewall.sh" || true
  bash "${REPO_ROOT}/scripts/verify-warmup-api-lan.sh" || true
fi

echo ""
echo ">>> register server in api-csgo (pool=${CLUTCH_SERVER_POOL})"
bash "${REPO_ROOT}/scripts/register-local-server.sh" || true

echo ""
echo "=== Health ==="
sleep 1
curl -sf "http://127.0.0.1:${PORT:-3001}/health" && echo "" || \
  echo "WARN: api não responde :${PORT:-3001}"

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  "${REPO_ROOT}/scripts/test-gloves-sync.sh" "STEAM_1:0:203852188" || true
fi

if [[ "${SKIP_INGAME}" -eq 0 ]]; then
  echo ""
  echo ">>> reload plugins in-game"
  bash "${REPO_ROOT}/scripts/reload-clutch-skins-ingame.sh" || \
    echo "WARN: CS offline — rode reload quando subir"
fi

echo ""
echo "=========================================="
echo "  Deploy concluído — ${CLUTCH_SERVER_PROFILE}"
echo "=========================================="
echo "Site: add this VPS to CSGO_API_URLS (or CSGO_WARMUP_API_URL):"
echo "  http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<vps-ip>'):${PORT:-3001}"
echo "pm2 restart api-csgo --update-env  (após editar .env)"
