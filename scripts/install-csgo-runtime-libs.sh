#!/usr/bin/env bash
# Instala bibliotecas 32-bit exigidas pelo CS:GO srcds (libtier0.so → libstdc++.so.6).
# Rode na VPS como usuário com sudo (clutch) OU como csgo se tiver NOPASSWD.
#
# Uso:
#   bash scripts/install-csgo-runtime-libs.sh
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: apt-get não encontrado — só Ubuntu/Debian." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo não encontrado." >&2
  exit 1
fi

echo ">>> Habilitando arquitetura i386 (32-bit)"
sudo dpkg --add-architecture i386 2>/dev/null || true

echo ">>> apt update"
sudo apt-get update -qq

echo ">>> Instalando libs para srcds_linux (32-bit)"
PACKAGES=(
  lib32gcc-s1
  lib32stdc++6
  libc6-i386
  libstdc++6
  zlib1g:i386
)

if sudo apt-get install -y "${PACKAGES[@]}" 2>/dev/null; then
  echo "OK: pacotes base instalados."
else
  echo "WARN: alguns pacotes falharam — tentando conjunto estendido..."
  sudo apt-get install -y \
    lib32gcc-s1 lib32stdc++6 libc6-i386 libstdc++6 \
    zlib1g:i386 libssl3t64:i386 libcurl4t64:i386 libcurl4:i386 \
    libnghttp2-14:i386 libldap2:i386 libpsl5t64:i386 libpsl5:i386 \
    libssh-4:i386 librtmp1:i386 libbrotli1:i386 libidn2-0:i386 \
    2>/dev/null || true
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
if [[ -f "${SERVER_ROOT}/bin/libtier0.so" ]]; then
  echo ""
  echo ">>> ldd bin/libtier0.so"
  ldd "${SERVER_ROOT}/bin/libtier0.so" 2>&1 | grep -i 'not found' || echo "(libtier0: todas as libs encontradas)"
fi

if [[ -f "${SERVER_ROOT}/bin/srcds_linux" ]]; then
  echo ""
  echo ">>> ldd bin/srcds_linux"
  ldd "${SERVER_ROOT}/bin/srcds_linux" 2>&1 | grep -i 'not found' || echo "(srcds_linux: todas as libs encontradas)"
else
  echo ""
  echo "WARN: ${SERVER_ROOT}/bin/srcds_linux ainda não existe."
  echo "      Rode steamcmd: app_update 740 validate"
fi

echo ""
echo "Próximo passo (como csgo):"
echo "  cd ~/steamcmd && ./steamcmd.sh +force_install_dir ${SERVER_ROOT} +login anonymous +app_update 740 validate +quit"
echo "  cd ~/api-csgo && bash scripts/start-csgo-screen.sh"
