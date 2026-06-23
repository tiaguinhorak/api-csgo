#!/usr/bin/env bash
# Install CSGO_WeaponStickers + eItems on the CS:GO VPS (Linux).
#
# Uso:
#   cd ~/api-csgo && git pull
#   bash scripts/install-csgo-weaponstickers.sh
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

# Find .../addons/sourcemod/plugins inside an extracted tree and merge into CSGO.
merge_addons_tree() {
  local search_root="$1"
  local merged=0

  while IFS= read -r plugins_dir; do
    local sm_dir addons_dir
    sm_dir="$(dirname "${plugins_dir}")"
    addons_dir="$(dirname "${sm_dir}")"
    echo "Merging addons from ${addons_dir}"
    cp -a "${addons_dir}/." "${CSGO_ROOT}/addons/"
    merged=1
  done < <(find "${search_root}" -type d -path '*/sourcemod/plugins' 2>/dev/null)

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

install_weaponstickers_z1ntex() {
  echo ""
  echo ">>> Download WeaponStickers v1.3.6 (z1ntex .rar)"
  local extract_dir="${TMP_DIR}/z1ntex-clean"
  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"
  if ! curl -fsSL "${Z1NTEX_RAR_URL}" -o "${TMP_DIR}/weaponstickers.rar"; then
    return 1
  fi
  if command -v 7z >/dev/null 2>&1; then
    if ! 7z x -o"${extract_dir}" -y "${TMP_DIR}/weaponstickers.rar" >/dev/null; then
      return 1
    fi
  elif command -v unrar >/dev/null 2>&1; then
    if ! unrar x -o+ "${TMP_DIR}/weaponstickers.rar" "${extract_dir}/" >/dev/null; then
      return 1
    fi
  elif command -v unrar-free >/dev/null 2>&1; then
    if ! unrar-free x "${TMP_DIR}/weaponstickers.rar" "${extract_dir}/" >/dev/null; then
      return 1
    fi
  else
    echo "WARN: no unrar/7z — skipping z1ntex rar (quasemago zip fallback will run)"
    return 1
  fi
  merge_addons_tree "${extract_dir}"
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

echo "=== CSGO_WeaponStickers installer ==="
echo "CSGO_ROOT=${CSGO_ROOT}"

if ! has_weaponstickers_plugin; then
  if ! install_weaponstickers_z1ntex; then
    echo "WARN: z1ntex rar install failed (install unrar-free if needed)"
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
ls -la "${SM}/plugins/csgo_weaponstickers.smx" 2>/dev/null \
  || echo "ERROR: csgo_weaponstickers.smx missing — check unrar: sudo apt install unrar-free"
ls -la "${SM}/plugins/eItems.smx" "${SM}/plugins/eitems.smx" 2>/dev/null \
  || echo "WARN: eItems.smx missing"
ls -la "${SM}/extensions/PTaH.ext"*.so 2>/dev/null \
  || echo "WARN: PTaH extension missing"

if ! has_weaponstickers_plugin || ! has_eitems_plugin; then
  echo ""
  echo "ERROR: install incomplete — fix errors above and re-run." >&2
  exit 1
fi

echo ""
echo "=== Done ==="
echo "In screen:"
echo "  sm plugins load eItems"
echo "  sm plugins load csgo_weaponstickers"
echo "  sm plugins list | grep -iE 'eitems|weaponstickers'"
