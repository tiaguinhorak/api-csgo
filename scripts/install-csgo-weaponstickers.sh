#!/usr/bin/env bash
# Install CSGO_WeaponStickers + eItems on the CS:GO VPS (Linux).
#
# Uso:
#   cd ~/api-csgo && git pull
#   bash scripts/install-csgo-weaponstickers.sh
#   WEAPONSTICKERS_FORCE=1 bash scripts/install-csgo-weaponstickers.sh  # replace broken .smx
#
# Requer: curl, unzip (+ unrar ou 7z para o release z1ntex .rar)

set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"

detect_live_csgo_root() {
  local pid cwd exe dir
  pid="$(pgrep -n -x srcds_linux 2>/dev/null || pgrep -n -f 'srcds_linux.*csgo' 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  cwd="$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)"
  if [[ -n "${cwd}" && -d "${cwd}/addons/sourcemod/plugins" ]]; then
    echo "${cwd}"
    return 0
  fi
  exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
  dir="$(dirname "${exe}")"
  if [[ -d "${dir}/csgo/addons/sourcemod/plugins" ]]; then
    echo "${dir}/csgo"
    return 0
  fi
  if [[ -d "${dir}/addons/sourcemod/plugins" ]]; then
    echo "${dir}"
    return 0
  fi
  return 1
}

LIVE_ROOT="$(detect_live_csgo_root || true)"
if [[ -n "${LIVE_ROOT}" && "${LIVE_ROOT}" != "${CSGO_ROOT}" ]]; then
  echo "srcds is running from ${LIVE_ROOT} — installing there."
  CSGO_ROOT="${LIVE_ROOT}"
fi

SM="${CSGO_ROOT}/addons/sourcemod"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

Z1NTEX_RAR_URL="https://github.com/z1ntex/CSGO_WeaponStickers/releases/download/v1.3.6/sm.1.11%2B.WeaponStickers.v1.3.6.rar"
QUASEMAGO_ZIP_URL="https://github.com/quasemago/CSGO_WeaponStickers/releases/download/v1.0.13c/weaponstickers_1.0.13c.zip"
EITEMS_ZIP_URL="https://github.com/quasemago/eItems/releases/download/0.10_noapi/eItems_0.10.No.API.zip"
PTAH_LINUX_URL="https://github.com/komashchenko/PTaH/releases/download/v1.1.4/linux.zip"
RIPEXT_LINUX_URL="https://github.com/ErikMinekus/sm-ripext/releases/download/1.2.3/sm-ripext-1.2.3-linux.tar.gz"
MULTICOLORS_ZIP_URL="https://github.com/Bara/Multi-Colors/archive/refs/heads/master.zip"

if [[ ! -d "${SM}/plugins" ]]; then
  echo "SourceMod not found at ${SM}" >&2
  exit 1
fi

extract_archive() {
  local file="$1"
  local dest="$2"
  mkdir -p "${dest}"
  case "${file}" in
    *.zip)
      unzip -qo "${file}" -d "${dest}"
      ;;
    *.tar.gz)
      tar -xzf "${file}" -C "${dest}"
      ;;
    *.rar)
      if command -v unrar >/dev/null 2>&1; then
        unrar x -o+ "${file}" "${dest}/" >/dev/null
      elif command -v unrar-free >/dev/null 2>&1; then
        unrar-free x "${file}" "${dest}/" >/dev/null
      elif command -v 7z >/dev/null 2>&1; then
        7z x -o"${dest}" -y "${file}" >/dev/null
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "${file}" -C "${dest}"
      else
        echo "ERROR: need unrar, unrar-free, 7z, or bsdtar for ${file}" >&2
        echo "  Ubuntu: sudo apt install unrar-free   (or p7zip-full)" >&2
        return 1
      fi
      ;;
    *)
      echo "Unknown archive: ${file}" >&2
      return 1
      ;;
  esac
}

# Find addons/sourcemod (plugins, extensions, scripting) and merge into live server.
merge_addons_tree() {
  local search_root="$1"
  local merged=0

  while IFS= read -r sm_dir; do
    echo "Merging sourcemod tree from ${sm_dir}"
    cp -a "${sm_dir}/." "${SM}/"
    merged=1
  done < <(find "${search_root}" -type d -path '*/addons/sourcemod' 2>/dev/null)

  while IFS= read -r plugins_dir; do
    local sm_dir addons_dir
    sm_dir="$(dirname "${plugins_dir}")"
    addons_dir="$(dirname "${sm_dir}")"
    echo "Merging addons from ${addons_dir}"
    cp -a "${addons_dir}/." "${CSGO_ROOT}/addons/"
    merged=1
  done < <(find "${search_root}" -type d -path '*/sourcemod/plugins' ! -path '*/addons/sourcemod/plugins' 2>/dev/null)

  # Some releases ship csgo/addons/...
  if [[ -d "${search_root}/csgo/addons" ]]; then
    echo "Merging csgo/addons from ${search_root}/csgo"
    cp -a "${search_root}/csgo/addons/." "${CSGO_ROOT}/addons/"
    merged=1
  fi

  # Materials for sticker models (z1ntex rar often has csgo/materials)
  while IFS= read -r materials_dir; do
    local parent
    parent="$(dirname "${materials_dir}")"
    if [[ "$(basename "${parent}")" == "csgo" ]]; then
      echo "Merging materials from ${materials_dir}"
      mkdir -p "${CSGO_ROOT}/materials"
      cp -a "${materials_dir}/." "${CSGO_ROOT}/materials/"
      merged=1
    fi
  done < <(find "${search_root}" -type d -name 'materials' 2>/dev/null)

  if [[ "${merged}" -eq 1 ]]; then
    return 0
  fi
  return 1
}

has_weaponstickers_plugin() {
  [[ -f "${SM}/plugins/csgo_weaponstickers.smx" ]]
}

has_eitems_plugin() {
  [[ -f "${SM}/plugins/eItems.smx" || -f "${SM}/plugins/eitems.smx" ]]
}

has_ptah_extension() {
  compgen -G "${SM}/extensions/PTaH.ext*.so" >/dev/null 2>&1 \
    || [[ -f "${SM}/extensions/PTaH.ext.so" ]]
}

has_ripext_extension() {
  compgen -G "${SM}/extensions/rip.ext*.so" >/dev/null 2>&1 \
    || [[ -f "${SM}/extensions/rip.ext.so" ]]
}

has_multicolors_include() {
  [[ -f "${SM}/scripting/include/multicolors.inc" ]]
}

install_ripext() {
  echo ""
  echo ">>> REST in Pawn (sm-ripext) — required by eItems + WeaponStickers"
  curl -fsSL "${RIPEXT_LINUX_URL}" -o "${TMP_DIR}/ripext.tar.gz"
  extract_archive "${TMP_DIR}/ripext.tar.gz" "${TMP_DIR}/ripext"
  if ! merge_addons_tree "${TMP_DIR}/ripext"; then
    local rip_so
    rip_so="$(find "${TMP_DIR}/ripext" -name 'rip.ext*.so' -print -quit 2>/dev/null || true)"
    if [[ -n "${rip_so}" ]]; then
      echo "Copying ${rip_so} -> ${SM}/extensions/"
      mkdir -p "${SM}/extensions"
      cp -a "${rip_so}" "${SM}/extensions/"
    else
      echo "ERROR: rip.ext.so not found inside sm-ripext package" >&2
      return 1
    fi
  fi
  # Force load even before dependent plugins are up.
  touch "${SM}/extensions/rip.autoload" 2>/dev/null || true
}

install_multicolors() {
  echo ""
  echo ">>> Multi-Colors include (multicolors.inc)"
  curl -fsSL "${MULTICOLORS_ZIP_URL}" -o "${TMP_DIR}/multicolors.zip"
  extract_archive "${TMP_DIR}/multicolors.zip" "${TMP_DIR}/multicolors"
  merge_addons_tree "${TMP_DIR}/multicolors"
  # GitHub archive: Multi-Colors-master/addons/...
  if [[ -d "${TMP_DIR}/multicolors/Multi-Colors-master/addons" ]]; then
    cp -a "${TMP_DIR}/multicolors/Multi-Colors-master/addons/." "${CSGO_ROOT}/addons/"
  fi
}

extract_rar_to_dir() {
  local rar_file="$1"
  local dest="$2"
  rm -rf "${dest}"
  mkdir -p "${dest}"

  if command -v 7z >/dev/null 2>&1; then
    if 7z x -o"${dest}" -y "${rar_file}" >/dev/null 2>&1; then
      return 0
    fi
    echo "WARN: 7z failed on ${rar_file}" >&2
  fi

  if command -v bsdtar >/dev/null 2>&1; then
    if bsdtar -xf "${rar_file}" -C "${dest}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v unrar >/dev/null 2>&1; then
    if (cd "${dest}" && unrar x -o+ -y "${rar_file}") >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v unrar-free >/dev/null 2>&1; then
    # cd into dest avoids unrar-free mkpath "File exists" on nested folders
    if (cd "${dest}" && unrar-free x -o+ "${rar_file}") >/dev/null 2>&1; then
      return 0
    fi
  fi

  echo "ERROR: could not extract RAR — install p7zip-full: sudo apt install -y p7zip-full" >&2
  return 1
}

install_weaponstickers_z1ntex() {
  echo ""
  echo ">>> Download WeaponStickers v1.3.6 (z1ntex .rar)"
  local extract_dir="${TMP_DIR}/z1ntex-clean"
  if ! curl -fsSL "${Z1NTEX_RAR_URL}" -o "${TMP_DIR}/weaponstickers.rar"; then
    return 1
  fi
  if ! extract_rar_to_dir "${TMP_DIR}/weaponstickers.rar" "${extract_dir}"; then
    return 1
  fi
  if ! merge_addons_tree "${extract_dir}"; then
  local smx
    smx="$(find "${extract_dir}" -name 'csgo_weaponstickers.smx' -print -quit 2>/dev/null || true)"
    if [[ -n "${smx}" ]]; then
      echo "Copying plugin from ${smx}"
      cp -a "${smx}" "${SM}/plugins/csgo_weaponstickers.smx"
      return 0
    fi
    return 1
  fi
  return 0
}

install_weaponstickers_quasemago() {
  echo ""
  echo ">>> Fallback: WeaponStickers v1.0.13c (quasemago .zip)"
  curl -fsSL "${QUASEMAGO_ZIP_URL}" -o "${TMP_DIR}/weaponstickers.zip"
  extract_archive "${TMP_DIR}/weaponstickers.zip" "${TMP_DIR}/quasemago"
  merge_addons_tree "${TMP_DIR}/quasemago"
}

install_eitems() {
  echo ""
  echo ">>> Download eItems 0.10 No API"
  curl -fsSL "${EITEMS_ZIP_URL}" -o "${TMP_DIR}/eitems.zip"
  extract_archive "${TMP_DIR}/eitems.zip" "${TMP_DIR}/eitems"
  merge_addons_tree "${TMP_DIR}/eitems"
}

install_ptah() {
  echo ""
  echo ">>> PTaH extension (linux.zip v1.1.4)"
  curl -fsSL "${PTAH_LINUX_URL}" -o "${TMP_DIR}/ptah.zip"
  extract_archive "${TMP_DIR}/ptah.zip" "${TMP_DIR}/ptah"
  merge_addons_tree "${TMP_DIR}/ptah"
}

echo "=== CSGO_WeaponStickers installer (v2026-06-23-z1ntex-extract) ==="
echo "CSGO_ROOT=${CSGO_ROOT}"

if [[ "${WEAPONSTICKERS_FORCE:-0}" == "1" ]]; then
  echo "WEAPONSTICKERS_FORCE=1 — reinstalling csgo_weaponstickers.smx"
  rm -f "${SM}/plugins/csgo_weaponstickers.smx"
fi

if ! has_ripext_extension; then
  install_ripext
fi

if ! has_multicolors_include; then
  install_multicolors
fi

if ! has_weaponstickers_plugin; then
  if ! install_weaponstickers_z1ntex; then
    echo "WARN: z1ntex rar install failed (install p7zip-full or unrar-free)"
  fi
fi

if ! has_weaponstickers_plugin; then
  install_weaponstickers_quasemago
fi

if ! has_eitems_plugin; then
  install_eitems
fi

if ! has_ptah_extension; then
  install_ptah
fi

# Re-check deps after installs
if ! has_ripext_extension; then
  install_ripext
fi

echo ""
echo ">>> databases.cfg — csgo_weaponstickers SQLite"
DB_CFG="${SM}/configs/databases.cfg"
if [[ -f "${DB_CFG}" ]]; then
  if grep -q '"csgo_weaponstickers"' "${DB_CFG}"; then
    echo "csgo_weaponstickers entry already in databases.cfg"
  else
    cat >> "${DB_CFG}" <<'EOF'

"csgo_weaponstickers"
{
	"driver"		"sqlite"
	"database"		"csgo_weaponstickers"
}
EOF
    echo "Added csgo_weaponstickers block to databases.cfg"
  fi
else
  echo "WARN: ${DB_CFG} not found — add csgo_weaponstickers SQLite block manually"
fi

echo ""
echo ">>> core.cfg — FollowCSGOServerGuidelines"
CORE_CFG="${SM}/configs/core.cfg"
if [[ -f "${CORE_CFG}" ]]; then
  if grep -q '"FollowCSGOServerGuidelines"[[:space:]]*"no"' "${CORE_CFG}"; then
    echo "core.cfg OK"
  elif grep -q 'FollowCSGOServerGuidelines' "${CORE_CFG}"; then
    echo "WARN: set FollowCSGOServerGuidelines to \"no\" in ${CORE_CFG}"
  else
    printf '\n"FollowCSGOServerGuidelines" "no"\n' >> "${CORE_CFG}"
    echo "Added FollowCSGOServerGuidelines no"
  fi
fi

echo ""
echo ">>> csgo_weaponstickers.cfg — auto-apply on spawn"
mkdir -p "${CSGO_ROOT}/cfg/sourcemod"
STICKERS_CFG="${CSGO_ROOT}/cfg/sourcemod/csgo_weaponstickers.cfg"
if [[ ! -f "${STICKERS_CFG}" ]]; then
  cat > "${STICKERS_CFG}" <<'EOF'
// Clutch — stickers from site DB (no !stickers needed)
sm_weaponstickers_enabled "1"
sm_weaponstickers_flag ""
sm_weaponstickers_overrideview "1"
sm_weaponstickers_updateviewmodel "1"
sm_weaponstickers_reusetime "0"
sm_weaponstickers_inactive_days "0"
EOF
  echo "Created ${STICKERS_CFG}"
else
  for key in sm_weaponstickers_enabled sm_weaponstickers_overrideview sm_weaponstickers_updateviewmodel sm_weaponstickers_reusetime; do
    case "${key}" in
      sm_weaponstickers_enabled) val="1" ;;
      sm_weaponstickers_overrideview) val="1" ;;
      sm_weaponstickers_updateviewmodel) val="1" ;;
      sm_weaponstickers_reusetime) val="0" ;;
    esac
    if grep -q "^${key}" "${STICKERS_CFG}"; then
      sed -i "s|^${key}.*|${key} \"${val}\"|g" "${STICKERS_CFG}"
    else
      printf '%s "%s"\n' "${key}" "${val}" >> "${STICKERS_CFG}"
    fi
  done
  echo "Updated ${STICKERS_CFG}"
fi

STICKERS_DB="${SM}/data/sqlite/csgo_weaponstickers.sq3"
mkdir -p "$(dirname "${STICKERS_DB}")"
echo ""
echo "Stickers DB (plugin reads here): ${STICKERS_DB}"

echo ""
echo "=== Plugin files ==="
if has_weaponstickers_plugin; then
  ls -la "${SM}/plugins/csgo_weaponstickers.smx"
else
  echo "ERROR: csgo_weaponstickers.smx missing"
fi
if has_eitems_plugin; then
  ls -la "${SM}/plugins/eItems.smx" 2>/dev/null || ls -la "${SM}/plugins/eitems.smx"
else
  echo "WARN: eItems.smx missing — run install again or check eItems zip"
fi
if has_ptah_extension; then
  ls -la "${SM}/extensions/PTaH.ext"*.so 2>/dev/null | head -3
else
  echo "WARN: PTaH extension missing"
fi
if has_ripext_extension; then
  ls -la "${SM}/extensions/rip.ext"*.so 2>/dev/null | head -3
else
  echo "ERROR: rip.ext (REST in Pawn) missing — eItems and WeaponStickers will fail"
fi
if has_multicolors_include; then
  ls -la "${SM}/scripting/include/multicolors.inc"
else
  echo "WARN: multicolors.inc missing"
fi

if ! has_weaponstickers_plugin || ! has_eitems_plugin || ! has_ripext_extension; then
  echo ""
  echo "ERROR: install incomplete — fix errors above and re-run." >&2
  echo "  Tip: sudo apt install -y p7zip-full" >&2
  echo "  Tip: WEAPONSTICKERS_FORCE=1 bash scripts/install-csgo-weaponstickers.sh" >&2
  exit 1
fi

echo ""
echo "=== Done ==="
echo "Restart srcds OR in server console (order matters):"
echo "  sm exts list | grep -i rip"
echo "  sm plugins reload eItems"
echo "  sm plugins reload csgo_weaponstickers"
echo "  sm plugins list | grep -iE 'eitems|weaponstickers'"
echo ""
echo "If plugins still fail, full map change or: changelevel de_dust2"
