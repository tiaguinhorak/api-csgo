#!/usr/bin/env bash
# Instala Node.js 20+ (NodeSource) se não estiver no PATH.
# Uso: bash scripts/install-node.sh
set -euo pipefail

need_node() {
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi
  local major
  major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
  if [[ "${major}" -lt 18 ]]; then
    return 0
  fi
  return 1
}

if ! need_node; then
  echo "OK: Node $(node -v)"
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: Node 18+ necessário — instale manualmente (nvm ou nodesource)" >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo necessário para instalar Node via apt" >&2
  exit 1
fi

echo ">>> Instalando Node.js 20.x (NodeSource)"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

if ! need_node; then
  echo "OK: Node $(node -v) | npm $(npm -v)"
else
  echo "ERROR: Node ainda incompatível após instalação" >&2
  exit 1
fi
