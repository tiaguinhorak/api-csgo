#!/usr/bin/env bash
# Simula pipeline ranked (api-csgo → SQLite → site) sem entrar no CS:GO.
#
# Uso:
#   ./scripts/simulate-match-pipeline.sh --room-id <RankedMatchSession.id>
#   ./scripts/simulate-match-pipeline.sh --room-id cmxxx --steam 76561198367970104
#
# Obtenha room-id: no site, sessão ranked em starting/live (URL ou Admin).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
source_clutch_env "${REPO_ROOT}/.env"

npm run build --silent
node dist/tools/simulate-match-pipeline.js "$@"
