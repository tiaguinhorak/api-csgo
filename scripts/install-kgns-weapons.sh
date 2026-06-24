#!/usr/bin/env bash
# kgns Weapons & Knives (!ws) — same SQLite skin DB as ranked; required with z_clutch_skins_bridge.
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
KGNS_WEAPONS_ZIP="https://github.com/kgns/weapons/archive/refs/heads/master.zip"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ ! -d "${SM}/plugins" ]]; then
  echo "ERROR: SourceMod not found at ${SM}" >&2
  exit 1
fi

if [[ -f "${SM}/plugins/weapons.smx" && -f "${SM}/scripting/weapons.sp" ]]; then
  echo "weapons.smx + weapons.sp already present — patching natives if needed"
  CSGO_ROOT="${CSGO_ROOT}" bash "${REPO_ROOT}/scripts/patch-weapons-reload-native.sh"
  exit 0
fi

echo ">>> Download kgns/weapons (master)"
curl -fsSL "${KGNS_WEAPONS_ZIP}" -o "${TMP_DIR}/weapons.zip"
unzip -qo "${TMP_DIR}/weapons.zip" -d "${TMP_DIR}"

merged=0
while IFS= read -r sm_dir; do
  echo "Merging ${sm_dir}"
  cp -a "${sm_dir}/." "${SM}/"
  merged=1
done < <(find "${TMP_DIR}" -type d -path '*/addons/sourcemod' 2>/dev/null)

if [[ "${merged}" -eq 0 ]]; then
  echo "ERROR: could not find addons/sourcemod in kgns zip" >&2
  exit 1
fi

if [[ ! -f "${SM}/scripting/weapons.sp" ]]; then
  echo "ERROR: weapons.sp missing after merge" >&2
  exit 1
fi

echo ">>> Patch + compile weapons.smx (Clutch natives)"
CSGO_ROOT="${CSGO_ROOT}" bash "${REPO_ROOT}/scripts/patch-weapons-reload-native.sh"

if [[ ! -f "${SM}/plugins/weapons.smx" ]]; then
  echo "ERROR: weapons.smx not built" >&2
  exit 1
fi

echo "OK: weapons.smx installed ($(ls -la "${SM}/plugins/weapons.smx"))"
