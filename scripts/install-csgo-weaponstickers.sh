#!/usr/bin/env bash
# Install CSGO_WeaponStickers + eItems on the CS:GO VPS (Linux).
# Plugin: https://forums.alliedmods.net/showthread.php?t=327078
# (packaged via z1ntex/quasemago releases — see Z1NTEX_RAR_URL below)
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
RIPEXT_LINUX_URL="https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip"
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

has_multicolors_include() {
  [[ -f "${SM}/scripting/include/multicolors.inc" ]]
}

has_ptah_extension() {
  compgen -G "${SM}/extensions/PTaH.ext*.so" >/dev/null 2>&1 \
    || [[ -f "${SM}/extensions/PTaH.ext.so" ]]
}

has_ripext_extension() {
  [[ -n "$(ripext_so_path)" ]]
}

ripext_so_path() {
  local candidates=(
    "${SM}/extensions/rip.ext.so"
    "${SM}/extensions/ripext.ext.so"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done
  compgen -G "${SM}/extensions/rip.ext*.so" 2>/dev/null | head -1 || true
}

verify_ripext_ldd() {
  local rip_so
  rip_so="$(ripext_so_path)"
  if [[ -z "${rip_so}" || ! -f "${rip_so}" ]]; then
    echo "ERROR: rip.ext.so not found in ${SM}/extensions/" >&2
    return 1
  fi
  chmod u+x "${rip_so}" 2>/dev/null || true
  echo ""
  echo ">>> ldd ${rip_so}"
  if ! command -v ldd >/dev/null 2>&1; then
    echo "WARN: ldd not available — skipping dependency check"
    return 0
  fi
  local ldd_out
  ldd_out="$(ldd "${rip_so}" 2>&1)"
  echo "${ldd_out}"
  if echo "${ldd_out}" | grep -q 'not found'; then
    echo ""
    echo "ERROR: rip.ext cannot load — missing 32-bit system libraries (CS:GO srcds is 32-bit)." >&2
    echo "Run on VPS:" >&2
    echo "  sudo dpkg --add-architecture i386" >&2
    echo "  sudo apt update" >&2
    echo "  sudo apt install -y lib32stdc++6 lib32z1 zlib1g:i386 libssl3t64:i386 libcurl4:i386" >&2
    return 1
  fi
  return 0
}

verify_ripext_size() {
  local rip_so size
  rip_so="$(ripext_so_path)"
  if [[ -z "${rip_so}" || ! -f "${rip_so}" ]]; then
    return 1
  fi
  size="$(wc -c < "${rip_so}" | tr -d ' ')"
  echo "rip.ext.so size: ${size} bytes (sm-ripext 1.3.2 expects ~5008816)"
  if command -v file >/dev/null 2>&1; then
    local arch
    arch="$(file -b "${rip_so}")"
    echo "rip.ext.so arch: ${arch}"
    if [[ "${arch}" != *"32-bit"* ]]; then
      echo "ERROR: rip.ext.so is not 32-bit — CS:GO srcds cannot load it. Re-run installer." >&2
      return 1
    fi
  fi
  if [[ "${size}" -lt 4000000 ]]; then
    echo "ERROR: rip.ext.so is too small — likely wrong/corrupt build. Re-run installer." >&2
    return 1
  fi
  return 0
}

check_extensions_mount_exec() {
  local rip_so mount_opts
  rip_so="$(ripext_so_path)"
  if [[ -z "${rip_so}" ]]; then
    return 0
  fi
  if ! command -v findmnt >/dev/null 2>&1; then
    return 0
  fi
  mount_opts="$(findmnt -no OPTIONS -T "${rip_so}" 2>/dev/null || true)"
  if [[ -n "${mount_opts}" && "${mount_opts}" == *noexec* ]]; then
    echo ""
    echo "ERROR: ${rip_so} sits on a noexec mount (${mount_opts})." >&2
    echo "srcds cannot dlopen extensions there — remount with exec or move server off /home:" >&2
    echo "  sudo mount -o remount,exec $(findmnt -no TARGET -T "${rip_so}")" >&2
    return 1
  fi
  return 0
}

cleanup_linux_optional_extensions() {
  # Windows-only optional extensions — broken .so on Linux clutters sm exts list
  rm -f "${SM}/extensions/sourcescramble.ext.so" "${SM}/extensions/sourcescramble.autoload" 2>/dev/null || true
}

install_ripext_system_deps() {
  if ! command -v apt-get >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  echo ""
  echo ">>> Installing 32-bit system libs for rip.ext (sudo)..."
  sudo dpkg --add-architecture i386 2>/dev/null || true
  sudo apt-get update -qq 2>/dev/null || true
  if sudo apt-get install -y lib32stdc++6 lib32z1 zlib1g:i386 libssl3t64:i386 libcurl4t64:i386 \
    libnghttp2-14:i386 libldap2:i386 libpsl5t64:i386 libssh-4:i386 librtmp1:i386 \
    libbrotli1:i386 libidn2-0:i386 2>/dev/null; then
    return 0
  fi
  if sudo apt-get install -y lib32stdc++6 lib32z1 zlib1g:i386 libssl3t64:i386 libcurl4:i386 \
    libnghttp2:i386 libldap2:i386 libpsl5:i386 libssh-4:i386 libldap-2.5-0:i386 librtmp1:i386 \
    libbrotli1:i386 2>/dev/null; then
    return 0
  fi
  if sudo apt-get install -y lib32stdc++6 lib32z1 zlib1g:i386 libssl1.1:i386 libcurl4:i386 2>/dev/null; then
    return 0
  fi
  return 1
}

install_ripext() {
  echo ""
  echo ">>> REST in Pawn (sm-ripext 1.3.2) — required by eItems + WeaponStickers"
  rm -f "${SM}/extensions/rip.ext"*.so "${SM}/extensions/ripext.ext"*.so 2>/dev/null || true
  curl -fsSL "${RIPEXT_LINUX_URL}" -o "${TMP_DIR}/ripext.zip"
  extract_archive "${TMP_DIR}/ripext.zip" "${TMP_DIR}/ripext"
  if ! merge_addons_tree "${TMP_DIR}/ripext"; then
    echo "WARN: merge_addons_tree failed for ripext — copying .so files manually"
  fi
  mkdir -p "${SM}/extensions"
  local rip_32="${TMP_DIR}/ripext/addons/sourcemod/extensions/rip.ext.so"
  if [[ -f "${rip_32}" ]]; then
    echo "Copying 32-bit ${rip_32} -> ${SM}/extensions/"
    cp -a "${rip_32}" "${SM}/extensions/"
  else
    while IFS= read -r -d '' so_file; do
      if [[ "${so_file}" == *"/x64/"* ]]; then
        continue
      fi
      echo "Copying ${so_file} -> ${SM}/extensions/"
      cp -a "${so_file}" "${SM}/extensions/"
    done < <(find "${TMP_DIR}/ripext" -name 'rip.ext.so' -path '*/extensions/*' ! -path '*/x64/*' -print0 2>/dev/null)
  fi
  # Never ship x64 extension binaries into CS:GO srcds (32-bit) extensions folder
  rm -rf "${SM}/extensions/x64" 2>/dev/null || true
  # CA bundle for HTTPS (ripext 1.0.3+)
  while IFS= read -r -d '' cfg_dir; do
    if [[ -d "${cfg_dir}" ]]; then
      mkdir -p "${SM}/configs/ripext"
      cp -a "${cfg_dir}/." "${SM}/configs/ripext/" 2>/dev/null || true
    fi
  done < <(find "${TMP_DIR}/ripext" -type d -path '*/configs/ripext' -print0 2>/dev/null)
  touch "${SM}/extensions/rip.autoload" 2>/dev/null || true
  if [[ -n "$(ripext_so_path)" ]]; then
  chown csgo:csgo "${SM}/extensions/rip.ext"*.so 2>/dev/null || true
  chmod u+x "${SM}/extensions/rip.ext"*.so 2>/dev/null || true
  fi
  if [[ -d "${SM}/configs/ripext" ]]; then
    chown -R csgo:csgo "${SM}/configs/ripext" 2>/dev/null || true
  fi
  if [[ -z "$(ripext_so_path)" ]]; then
    echo "ERROR: rip.ext.so not found inside sm-ripext package" >&2
    return 1
  fi
  return 0
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

echo "=== CSGO_WeaponStickers installer (v2026-06-23-ripext-ldd) ==="
echo "CSGO_ROOT=${CSGO_ROOT}"

if [[ "${WEAPONSTICKERS_FORCE:-0}" == "1" ]]; then
  echo "WEAPONSTICKERS_FORCE=1 — reinstalling csgo_weaponstickers.smx"
  rm -f "${SM}/plugins/csgo_weaponstickers.smx"
fi

# Do not install ripext here — other packages may overwrite extensions/*.so

if ! has_multicolors_include; then
  install_multicolors
fi

if ! has_weaponstickers_plugin; then
  if ! install_weaponstickers_z1ntex; then
    echo "WARN: z1ntex SM 1.11 install failed (sudo apt install -y p7zip-full)"
    if [[ "${WEAPONSTICKERS_FORCE:-0}" == "1" ]]; then
      echo "ERROR: WEAPONSTICKERS_FORCE=1 but z1ntex not installed — fix RAR extractor and re-run." >&2
      exit 1
    fi
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

# Install ripext LAST — weaponstickers/eItems merges must not overwrite rip.ext.so
install_ripext
cleanup_linux_optional_extensions

echo ""
echo ">>> rip.ext checks (size, mount, ldd)"
verify_ripext_size || true
check_extensions_mount_exec || true
if ! verify_ripext_ldd; then
  install_ripext_system_deps || true
  if ! verify_ripext_ldd; then
    echo ""
    echo "ERROR: rip.ext still missing system libraries — stickers will not work until fixed." >&2
    echo "Install i386 libs manually (see ldd output above), then restart srcds." >&2
  fi
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
  verify_ripext_ldd || true
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
echo "Extensions (rip.ext) only load on srcds start — restart srcds or changelevel."
echo "Then in server console:"
echo "  sm exts list"
echo "  sm plugins load eItems"
echo "  sm plugins load csgo_weaponstickers"
echo "  sm plugins list | grep -iE 'eitems|weaponstickers'"
echo ""
echo "If rip.ext shows FAILED, run: ldd ${SM}/extensions/rip.ext.so"
echo "and install any 'not found' i386 packages (see verify_ripext_ldd output above)."
