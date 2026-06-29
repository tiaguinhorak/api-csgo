#!/usr/bin/env bash
set -euo pipefail

# Push agent models from a PC with CS:GO / CS:GO Legacy (loose files or VPK).
#
# Usage (Git Bash on Windows):
#   VPS_HOST=csgo@19520 ./scripts/push-agent-models-from-pc.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  )
  local root game
  for root in "${steam_roots[@]}"; do
    for game in \
      "csgo legacy/csgo" \
      "Counter-Strike Global Offensive/csgo" \
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

TARBALL="${TMPDIR:-/tmp}/custom_player.tgz"
rm -f "${TARBALL}"

SRC="$(find_custom_player || true)"
if [[ -n "${SRC}" ]]; then
  echo ">>> Loose files: ${SRC}"
  tar czf "${TARBALL}" -C "$(dirname "${SRC}")" custom_player
else
  echo ">>> No loose custom_player — extracting from pak01_dir.vpk"
  if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python required for VPK extract (pip install vpk)" >&2
    exit 1
  fi
  resolve_python() {
    for c in python3 python py; do
      if command -v "${c}" >/dev/null 2>&1; then
        echo "${c}"
        return 0
      fi
    done
    return 1
  }
  PY="$(resolve_python || true)"
  if [[ -z "${PY}" ]]; then
    echo "ERROR: python not found (install Python 3, then: pip install vpk)" >&2
    exit 1
  fi
  if [[ "${PY}" == py ]]; then
    PY="py -3"
  fi
  ${PY} -m pip install -q vpk 2>/dev/null || ${PY} -m pip install vpk
  ${PY} "${REPO_ROOT}/scripts/extract-agent-models-from-csgo.py" \
    --output-tarball "${TARBALL}"
fi

echo ">>> Uploading to ${VPS_HOST}:/tmp/custom_player.tgz"
scp "${TARBALL}" "${VPS_HOST}:/tmp/custom_player.tgz"

echo ">>> Extracting on VPS"
ssh "${VPS_HOST}" 'cd ~/api-csgo && git pull -q && ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz'

echo "Done."
