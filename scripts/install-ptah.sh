#!/usr/bin/env bash
# PTaH extension + include (required to compile/run z_clutch_skins_bridge).
set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
PTAH_LINUX_URL="https://github.com/komashchenko/PTaH/releases/download/v1.1.4/linux.zip"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

has_ptah_extension() {
  compgen -G "${SM}/extensions/PTaH.ext*.so" >/dev/null 2>&1 \
    || [[ -f "${SM}/extensions/PTaH.ext.so" ]]
}

has_ptah_include() {
  [[ -f "${SM}/scripting/include/PTaH.inc" ]]
}

if [[ ! -d "${SM}/extensions" ]]; then
  echo "ERROR: SourceMod not found at ${SM}" >&2
  exit 1
fi

if has_ptah_extension && has_ptah_include; then
  echo "PTaH already installed (extension + PTaH.inc)"
  ls -la "${SM}/extensions/PTaH.ext"*.so 2>/dev/null | head -3 || true
  exit 0
fi

echo ">>> Installing PTaH v1.1.4 (linux.zip)"
curl -fsSL "${PTAH_LINUX_URL}" -o "${TMP_DIR}/ptah.zip"
unzip -qo "${TMP_DIR}/ptah.zip" -d "${TMP_DIR}/ptah"

merged=0
while IFS= read -r sm_dir; do
  echo "Merging ${sm_dir}"
  cp -a "${sm_dir}/." "${SM}/"
  merged=1
done < <(find "${TMP_DIR}/ptah" -type d -path '*/addons/sourcemod' 2>/dev/null)

if [[ -d "${TMP_DIR}/ptah/addons/sourcemod" ]]; then
  cp -a "${TMP_DIR}/ptah/addons/sourcemod/." "${SM}/"
  merged=1
fi

if [[ "${merged}" -eq 0 ]]; then
  # Flat zip layout
  if compgen -G "${TMP_DIR}/ptah/**/*.so" >/dev/null 2>&1; then
    find "${TMP_DIR}/ptah" -name 'PTaH.ext*.so' -exec cp -a {} "${SM}/extensions/" \;
    find "${TMP_DIR}/ptah" -name 'PTaH.inc' -exec cp -a {} "${SM}/scripting/include/" \;
    merged=1
  fi
fi

if ! has_ptah_extension; then
  echo "ERROR: PTaH extension .so not found after install" >&2
  find "${TMP_DIR}/ptah" -type f 2>/dev/null | head -20 >&2
  exit 1
fi

if ! has_ptah_include; then
  echo "ERROR: PTaH.inc not found after install" >&2
  exit 1
fi

chmod u+x "${SM}/extensions/PTaH.ext"*.so 2>/dev/null || true
echo "OK: PTaH installed"
ls -la "${SM}/extensions/PTaH.ext"*.so 2>/dev/null | head -3
echo "     ${SM}/scripting/include/PTaH.inc"
