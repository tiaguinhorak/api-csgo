#!/usr/bin/env bash
set -euo pipefail

# Compila e instala clutch_match_tracker (stats ranked + auto-finish).
#
# Uso:
#   cd ~/api-csgo && git pull
#   ./scripts/install-clutch-match-tracker.sh

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SP_SRC="${REPO_ROOT}/sourcemod/clutch_match_tracker.sp"

if [[ ! -f "${SP_SRC}" ]]; then
  echo "Missing ${SP_SRC}" >&2
  exit 1
fi

if [[ ! -d "${SM}/scripting" ]]; then
  echo "SourceMod not found at ${SM}" >&2
  exit 1
fi

SPCOMP="${SM}/scripting/spcomp"
if [[ ! -x "${SPCOMP}" ]]; then
  SPCOMP="${SM}/scripting/spcomp64"
fi
if [[ ! -x "${SPCOMP}" ]]; then
  echo "spcomp not found" >&2
  exit 1
fi

cp "${SP_SRC}" "${SM}/scripting/clutch_match_tracker.sp"
"${SPCOMP}" "${SM}/scripting/clutch_match_tracker.sp" -o"${SM}/plugins/clutch_match_tracker.smx"

echo "Installed ${SM}/plugins/clutch_match_tracker.smx"
echo "Reload: sm plugins reload clutch_match_tracker"
