#!/usr/bin/env bash
# Bootstrap .env for local dev (WSL or Linux). Does not install CS:GO.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ROOT="$(cd "${REPO_ROOT}/../site" 2>/dev/null && pwd || true)"

echo "=== Clutch setup-local-dev ==="

if [[ ! -f "${REPO_ROOT}/.env" ]]; then
  if [[ -f "${REPO_ROOT}/.env.local.example" ]]; then
    cp "${REPO_ROOT}/.env.local.example" "${REPO_ROOT}/.env"
    echo "Created api-csgo/.env from .env.local.example"
  else
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
    echo "Created api-csgo/.env from .env.example"
  fi
else
  echo "api-csgo/.env already exists — not overwritten"
fi

if [[ -n "${SITE_ROOT}" && -f "${SITE_ROOT}/env.local.example" ]]; then
  if [[ ! -f "${SITE_ROOT}/.env" ]]; then
    cp "${SITE_ROOT}/env.local.example" "${SITE_ROOT}/.env"
    echo "Created site/.env from env.local.example — EDIT DATABASE_URL and STEAM_API_KEY"
  else
    echo "site/.env already exists — not overwritten"
  fi
fi

cd "${REPO_ROOT}"
npm install
npm run build

echo ""
echo ">>> Next steps (see LOCAL-DEV.md in CsgoPage root):"
echo "  1) Edit site/.env — DATABASE_URL (VPS Postgres), STEAM_API_KEY"
echo "  2) Edit api-csgo/.env — CSGO_SKINS_SYNC_KEY must match site"
echo "  3) WSL: ./install.sh --start-game  (CS:GO + SourceMod + plugins)"
echo "  4) api-csgo: npm run pm2:start  (or: node dist/index.js)"
echo "  5) site: npm run dev"
echo "  6) bash scripts/verify-local-stack.sh"
echo ""
echo "Full CS install (WSL): cd ~/api-csgo && ./install.sh"
