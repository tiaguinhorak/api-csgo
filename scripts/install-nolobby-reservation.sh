#!/usr/bin/env bash
# NoLobbyReservation — fix "lobby id ffffffffffffffff" / loading screen → menu.
# https://github.com/eldoradoel/NoLobbyReservation
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

CSGO_ROOT="${CSGO_ROOT:-${CSGO_SERVER_DIR:-/home/csgo/server}/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
BASE_URL="https://raw.githubusercontent.com/eldoradoel/NoLobbyReservation/master/csgo/addons/sourcemod"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

if [[ ! -d "${SM}/scripting" ]]; then
  echo "ERROR: SourceMod not found at ${SM}" >&2
  exit 1
fi

SPCOMP="${SM}/scripting/spcomp"
if [[ ! -x "${SPCOMP}" ]]; then
  SPCOMP="${SM}/scripting/spcomp64"
fi
if [[ ! -x "${SPCOMP}" ]]; then
  echo "ERROR: spcomp not found under ${SM}/scripting" >&2
  exit 1
fi

echo ">>> Download NoLobbyReservation (eldoradoel)"
curl -fsSL "${BASE_URL}/gamedata/nolobbyreservation.games.txt" \
  -o "${SM}/gamedata/nolobbyreservation.games.txt"
curl -fsSL "${BASE_URL}/scripting/nolobbyreservation.sp" \
  -o "${SM}/scripting/nolobbyreservation.sp"

echo ">>> Compile nolobbyreservation.smx"
(
  cd "${SM}/scripting"
  "${SPCOMP}" nolobbyreservation.sp -o"${SM}/plugins/nolobbyreservation.smx"
)

if [[ ! -f "${SM}/plugins/nolobbyreservation.smx" ]]; then
  echo "ERROR: compile failed — check SourceMod logs" >&2
  exit 1
fi

echo "OK: ${SM}/plugins/nolobbyreservation.smx"
echo "Restart srcds or in server console: sm plugins load nolobbyreservation"
echo "Then connect again — lobby id ffffffffffffffff should be gone."
