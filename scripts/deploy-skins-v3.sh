#!/usr/bin/env bash
set -euo pipefail

# Atalho — mesmo que ./deploy.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT}/deploy.sh" "$@"
