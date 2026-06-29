#!/usr/bin/env bash
set -euo pipefail

# Push models/player/custom_player from a Windows/Linux PC with CS:GO installed to the VPS.
#
# Usage (Git Bash on Windows):
#   VPS_HOST=csgo@19520 ./scripts/push-agent-models-from-pc.sh
#   CSGO_CLIENT_CSGO="C:/.../csgo" VPS_HOST=csgo@19520 ./scripts/push-agent-models-from-pc.sh

VPS_HOST="${VPS_HOST:-}"
if [[ -z "${VPS_HOST}" ]]; then
  echo "ERROR: set VPS_HOST, e.g. VPS_HOST=csgo@19520" >&2
  exit 1
fi

find_custom_player() {
  local candidates=()
  if [[ -n "${CSGO_CLIENT_CSGO:-}" ]]; then
    candidates+=("${CSGO_CLIENT_CSGO}/models/player/custom_player")
  fi
  local steam_roots=(
    "${PROGRAMFILES_X86:-/c/Program Files (x86)}/Steam/steamapps/common"
    "${HOME}/.steam/steam/steamapps/common"
    "${HOME}/.local/share/Steam/steamapps/common"
  )
  local root game
  for root in "${steam_roots[@]}"; do
    for game in \
      "Counter-Strike Global Offensive/csgo" \
      "csgo legacy/csgo" \
      "Counter-Strike Global Offensive Beta/csgo"; do
      candidates+=("${root}/${game}/models/player/custom_player")
    done
  done
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "${c}" ]] && find "${c}" -name '*.mdl' -print -quit 2>/dev/null | grep -q .; then
      echo "${c}"
      return 0
    fi
  done
  return 1
}

SRC="$(find_custom_player || true)"
if [[ -z "${SRC}" ]]; then
  echo "ERROR: custom_player not found. Install CS:GO / CS:GO Legacy on Steam, or set:" >&2
  echo "  CSGO_CLIENT_CSGO='C:/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/csgo'" >&2
  exit 1
fi

TARBALL="${TMPDIR:-/tmp}/custom_player.tgz"
echo ">>> Source: ${SRC}"
echo ">>> Creating ${TARBALL}"
rm -f "${TARBALL}"
tar czf "${TARBALL}" -C "$(dirname "${SRC}")" custom_player

echo ">>> Uploading to ${VPS_HOST}:/tmp/custom_player.tgz"
scp "${TARBALL}" "${VPS_HOST}:/tmp/custom_player.tgz"

echo ">>> Extracting on VPS"
ssh "${VPS_HOST}" 'cd ~/api-csgo && ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz'

echo "Done."
