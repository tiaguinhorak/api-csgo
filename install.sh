#!/usr/bin/env bash
# First-time Clutch VPS setup — then edit .env and run ./deploy.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=========================================="
echo "  Clutch — instalação VPS (primeira vez)"
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
echo ">>> Edite .env antes do deploy:"
echo "    SERVER_PROFILE=ranked|warmup|deathmatch|surf|..."
echo "    CSGO_SKINS_SYNC_KEY (igual ao site)"
echo "    CLUTCH_SITE_URL, CSGO_RCON_PASSWORD, CSGO_GSLT_TOKEN"
echo "    CLUTCH_CS_SCREEN, SERVER_NAME, SERVER_MODE_LABEL"
echo ""

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js 18+ required (apt install nodejs ou nvm)" >&2
  exit 1
fi

echo "Node: $(node -v)"

chmod +x "${REPO_ROOT}/deploy.sh" "${REPO_ROOT}/scripts/"*.sh 2>/dev/null || true

bash "${REPO_ROOT}/scripts/ensure-profile-env.sh"

echo ""
echo ">>> Running unified deploy..."
exec bash "${REPO_ROOT}/scripts/deploy-unified.sh" "$@"
