#!/usr/bin/env bash
# CS:GO srcds ships an old bin/libgcc_s.so.1 that breaks system lib32stdc++6 on Ubuntu 20.04+.
# Rename it so the OS lib32gcc-s1 is used (see CubeCoders / LinuxGSM fix_csgo.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SERVER_ROOT="${CSGO_SERVER_DIR:-/home/csgo/server}"
BIN="${SERVER_ROOT}/bin"
LIBGCC="${BIN}/libgcc_s.so.1"

if [[ ! -d "${BIN}" ]]; then
  echo "WARN: ${BIN} não existe — instale o CS:GO (app 740) primeiro." >&2
  exit 0
fi

if [[ -f "${LIBGCC}" ]]; then
  mv -f "${LIBGCC}" "${LIBGCC}.bak"
  echo "OK: ${LIBGCC} → libgcc_s.so.1.bak (usa lib32gcc-s1 do sistema)"
elif [[ -f "${LIBGCC}.bak" ]]; then
  echo "OK: libgcc_s.so.1 já renomeado (.bak)"
else
  echo "WARN: ${LIBGCC} não encontrado"
fi

if [[ -f "${BIN}/libtier0.so" ]]; then
  if ldd "${BIN}/libtier0.so" 2>&1 | grep -qi 'not found\|GCC_7'; then
    echo "WARN: libtier0 ainda com problema de libs — rode install-csgo-runtime-libs.sh" >&2
    ldd "${BIN}/libtier0.so" 2>&1 | grep -iE 'not found|GCC_' || true
    exit 1
  fi
  echo "OK: libtier0.so carrega sem erro de libgcc"
fi
