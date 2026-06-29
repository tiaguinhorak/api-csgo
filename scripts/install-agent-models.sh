#!/usr/bin/env bash
set -euo pipefail

# Install CS:GO agent player models (models/player/custom_player/).
#
# Steam app 740 (dedicated server) does NOT ship these files — only the full
# client (app 730) or a manual copy from a PC with CS:GO installed works.
#
# Usage:
#   ./scripts/install-agent-models.sh
#   CSGO_CLIENT_CSGO=/path/to/csgo ./scripts/install-agent-models.sh
#
# Env:
#   CSGO_ROOT          — server game dir (default /home/csgo/server/csgo)
#   CSGO_CLIENT_CSGO   — existing client csgo/ with models (skip Steam download)
#   CSGO_CLIENT_INSTALL — staging dir for app 730 download (default ~/csgo-client)
#   STEAMCMD           — path to steamcmd.sh
#   CSGO_FASTDL_ROOT   — optional; mirror custom_player here (e.g. nginx fastdl root)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
DEST="${CSGO_ROOT}/models/player/custom_player"
CLIENT_INSTALL="${CSGO_CLIENT_INSTALL:-${HOME}/csgo-client}"
STEAMCMD="${STEAMCMD:-${HOME}/steamcmd/steamcmd.sh}"

if [[ ! -x "${STEAMCMD}" ]]; then
  STEAMCMD="/home/csgo/steamcmd/steamcmd.sh"
fi

find_client_custom_player() {
  local base="$1"
  local candidates=(
    "${base}/models/player/custom_player"
    "${base}/csgo/models/player/custom_player"
    "${base}/game/csgo/models/player/custom_player"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "${c}" ]] && find "${c}" -name '*.mdl' -print -quit 2>/dev/null | grep -q .; then
      echo "${c}"
      return 0
    fi
  done
  return 1
}

copy_tree() {
  local src="$1"
  echo ">>> Copying ${src} -> ${DEST}"
  mkdir -p "$(dirname "${DEST}")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${src}/" "${DEST}/"
  else
    rm -rf "${DEST}"
    cp -a "${src}" "${DEST}"
  fi
}

mirror_fastdl() {
  if [[ -z "${CSGO_FASTDL_ROOT:-}" ]]; then
    return 0
  fi
  local fastdl_dest="${CSGO_FASTDL_ROOT}/models/player/custom_player"
  echo ">>> Mirroring to fastdl: ${fastdl_dest}"
  mkdir -p "$(dirname "${fastdl_dest}")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${DEST}/" "${fastdl_dest}/"
  else
    rm -rf "${fastdl_dest}"
    cp -a "${DEST}" "${fastdl_dest}"
  fi
}

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "WARN: srcds_linux is running — stop the server before replacing models." >&2
fi

echo "=== Install agent models (custom_player) ==="
echo "Server:  ${DEST}"
echo ""

SRC=""
if [[ -n "${CSGO_CLIENT_CSGO:-}" ]]; then
  SRC="$(find_client_custom_player "${CSGO_CLIENT_CSGO}" || true)"
  if [[ -z "${SRC}" ]]; then
    echo "ERROR: CSGO_CLIENT_CSGO=${CSGO_CLIENT_CSGO} has no models/player/custom_player" >&2
    exit 1
  fi
  echo "Using local client path: ${SRC}"
else
  SRC="$(find_client_custom_player "${CLIENT_INSTALL}" || true)"
  if [[ -z "${SRC}" ]]; then
    if [[ ! -x "${STEAMCMD}" ]]; then
      echo "ERROR: steamcmd not found at ${STEAMCMD}" >&2
      exit 1
    fi
    echo "No client models found — downloading CS:GO client (app 730) to ${CLIENT_INSTALL}"
    echo "    (large download; only custom_player will be copied to the server)"
    echo ""
    mkdir -p "${CLIENT_INSTALL}"
    set +e
    "${STEAMCMD}" \
      +force_install_dir "${CLIENT_INSTALL}" \
      +login anonymous \
      +app_update 730 validate \
      +quit
    STEAM_EXIT=$?
    set -e
    if [[ "${STEAM_EXIT}" -ne 0 ]]; then
      echo ""
      echo "WARN: app_update 730 exited ${STEAM_EXIT} — client may no longer be on SteamCMD." >&2
      echo "Copy from a PC with CS:GO installed:" >&2
      echo "  scp -r '.../csgo/models/player/custom_player' csgo@server:${CSGO_ROOT}/models/player/" >&2
      exit 1
    fi
    SRC="$(find_client_custom_player "${CLIENT_INSTALL}" || true)"
    if [[ -z "${SRC}" ]]; then
      echo "ERROR: app 730 finished but custom_player not found under ${CLIENT_INSTALL}" >&2
      echo "List install dir:" >&2
      ls -la "${CLIENT_INSTALL}" >&2 || true
      exit 1
    fi
    echo "Found after download: ${SRC}"
  else
    echo "Using cached client staging: ${SRC}"
  fi
fi

copy_tree "${SRC}"
mirror_fastdl

count="$(find "${DEST}" -name '*.mdl' 2>/dev/null | wc -l | tr -d ' ')"
echo ""
echo "OK: ${count} .mdl files in ${DEST}"
echo "Run: ./scripts/verify-agent-models.sh"
