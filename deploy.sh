#!/usr/bin/env bash
# Deploy completo Clutch — um comando para qualquer tipo de servidor.
#
# Uso:
#   cd ~/api-csgo && ./install.sh     # primeira vez
#   cd ~/api-csgo && ./deploy.sh     # atualizar
#
# Configure apenas .env (SERVER_PROFILE, keys, RCON, screen name).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/scripts/deploy-unified.sh" "$@"
