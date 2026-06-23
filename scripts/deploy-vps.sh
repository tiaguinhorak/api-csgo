#!/usr/bin/env bash
set -euo pipefail

# Deploy completo na VPS: git pull → build api-csgo → pm2 → plugin → reload in-game.
#
# Uso (como usuário csgo na VPS):
#   cd ~/api-csgo && ./scripts/deploy-vps.sh
#
# Opções:
#   --skip-pull          não roda git pull
#   --skip-ingame        não recarrega plugin no screen do CS
#   --skip-plugin        só api (npm build + pm2), sem compilar plugin
#
# Exemplos:
#   ./scripts/deploy-vps.sh
#   ./scripts/deploy-vps.sh --skip-ingame

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
      sed -n '1,20p' "$0"
      exit 0
    ;;
    *)
      echo "Unknown option: ${arg}" >&2
      exit 1
    ;;
  esac
done

chmod +x "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

echo "=== Clutch VPS deploy (api-csgo) ==="
echo "Repo: ${REPO_ROOT}"

if [[ "${SKIP_PULL}" -eq 0 && -d .git ]]; then
  echo ""
  echo ">>> git pull"
  git pull --ff-only
fi

if [[ -d .git ]]; then
  echo "Git: $(git rev-parse --short HEAD) on $(git branch --show-current 2>/dev/null || echo '?')"
fi

EXPECTED_VERSION="$(grep -E '#define PLUGIN_VERSION' sourcemod/clutch_skins_bridge.sp | sed 's/.*"\(.*\)".*/\1/')"
echo "Plugin source version: ${EXPECTED_VERSION}"

if [[ ! -f package.json ]]; then
  echo "Not in api-csgo repo" >&2
  exit 1
fi

echo ""
echo ">>> npm install"
npm install --no-audit --no-fund

echo ""
echo ">>> npm run build"
npm run build

if ! grep -q 'gloves: result.gloves' dist/routes/csgo-skins-push.js; then
  echo "ERROR: dist build missing gloves sync — check git pull / build errors" >&2
  exit 1
fi

if command -v pm2 >/dev/null 2>&1; then
  echo ""
  echo ">>> pm2 (api-csgo)"
  "${REPO_ROOT}/scripts/pm2-ensure-api-csgo.sh"
else
  echo "WARN: pm2 not found — restart api-csgo manually"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

echo ""
echo ">>> verify live API matches dist"
if ! "${REPO_ROOT}/scripts/verify-api-running-build.sh"; then
  if command -v pm2 >/dev/null 2>&1; then
    echo ""
    echo ">>> stale process detected — running pm2-recover.sh"
    "${REPO_ROOT}/scripts/pm2-recover.sh"
    sleep 2
    "${REPO_ROOT}/scripts/verify-api-running-build.sh"
  else
    exit 1
  fi
fi

if [[ -z "${CSGO_SKINS_SYNC_KEY:-}" && -z "${API_KEY:-}" ]]; then
  echo ""
  echo "WARN: No CSGO_SKINS_SYNC_KEY or API_KEY in .env — site push may get HTTP 401"
fi

echo ""
echo ">>> sync weapons_english.cfg from site catalog"
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  bash "${REPO_ROOT}/scripts/sync-weapons-cfg-from-site.sh" || {
    echo "WARN: weapons cfg sync failed — run ./scripts/sync-weapons-cfg-from-site.sh after fixing CLUTCH_SITE_URL" >&2
  }
else
  echo "Skip (no CSGO_SKINS_SYNC_KEY)"
fi

echo ""
echo ">>> server branding (host_url / MOTD)"
bash "${REPO_ROOT}/scripts/ensure-clutch-server-branding.sh" || {
  echo "WARN: server branding script failed" >&2
}

if [[ "${SKIP_PLUGIN}" -eq 0 ]]; then
  echo ""
  echo ">>> install clutch_skins_bridge plugin"
  "${REPO_ROOT}/scripts/install-clutch-skins-bridge.sh"

  echo ""
  echo ">>> install CSGO_WeaponStickers + eItems (optional — skip if already installed)"
  if [[ -f "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" ]]; then
    bash "${REPO_ROOT}/scripts/install-csgo-weaponstickers.sh" || {
      echo "WARN: install-csgo-weaponstickers.sh failed — run manually after fixing deps" >&2
    }
  fi
fi

echo ""
echo "=== Health check ==="
sleep 1
curl -sf "http://127.0.0.1:${PORT:-3000}/health" && echo "" || echo "WARN: api-csgo not responding on :${PORT:-3000}"

echo ""
echo "=== Gloves sync test (optional) ==="
if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  "${REPO_ROOT}/scripts/test-gloves-sync.sh" "STEAM_1:0:203852188" || true
else
  echo "Skip (no CSGO_SKINS_SYNC_KEY)"
fi

if [[ "${SKIP_INGAME}" -eq 0 ]]; then
  echo ""
  echo ">>> reload plugin in-game (screen)"
  if "${REPO_ROOT}/scripts/reload-clutch-skins-ingame.sh"; then
    echo "In-game reload OK."
  else
    echo "WARN: in-game reload skipped or failed (CS screen offline?)."
    echo "  When server is up: ./scripts/reload-clutch-skins-ingame.sh"
  fi
fi

echo ""
echo "=== Deploy finished ==="
echo "Plugin version expected: ${EXPECTED_VERSION}"
echo "Verify in screen: sm plugins info z_clutch_skins_bridge"
echo "After editing .env: pm2 restart api-csgo --update-env"
