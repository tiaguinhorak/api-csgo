#!/usr/bin/env bash
# Deploy completo Clutch na VPS — um único comando.
#
# Uso (usuário csgo):
#   cd ~/api-csgo && ./deploy.sh
#
# Faz tudo: git pull → build api-csgo → pm2 → sync allowlist → plugins CS → reload in-game.
#
# Opções: --skip-pull | --skip-ingame | --skip-plugin | --help

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT}/scripts/deploy-vps.sh" "$@"
