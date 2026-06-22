#!/usr/bin/env bash
set -euo pipefail

# Atalho — deploy completo na VPS (git pull + api + plugin + reload in-game).
# Uso: cd ~/api-csgo && ./scripts/deploy-skins-v3.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/deploy-vps.sh" "$@"
