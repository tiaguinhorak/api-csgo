#!/usr/bin/env bash
# Install CSGO_WeaponStickers + eItems on the CS:GO VPS (Linux).
#
# Uso:
#   cd ~/api-csgo && git pull
#   bash scripts/install-csgo-weaponstickers.sh
#
# Requer: curl, unzip, unrar ou 7z (para extrair o release .rar)

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

WEAPONSTICKERS_RAR_URL="https://github.com/z1ntex/CSGO_WeaponStickers/releases/download/v1.3.6/sm.1.11%2B.WeaponStickers.v1.3.6.rar"
EITEMS_ZIP_URL="https://github.com/quasemago/eItems/releases/download/0.10_noapi/eItems_0.10.No.API.zip"
PTAH_URL="https://github.com/komashchenko/PTaH/releases/latest/download/PTaH.zip"

if [[ ! -d "${SM}/plugins" ]]; then
  echo "SourceMod not found at ${SM}" >&2
  exit 1
fi

extract_archive() {
  local file="$1"
  local dest="$2"
  case "${file}" in
    *.zip)
      unzip -qo "${file}" -d "${dest}"
      ;;
    *.rar)
      if command -v unrar >/dev/null 2>&1; then
        unrar x -o+ "${file}" "${dest}/" >/dev/null
      elif command -v 7z >/dev/null 2>&1; then
        7z x -o"${dest}" -y "${file}" >/dev/null
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "${file}" -C "${dest}"
      else
        echo "ERROR: need unrar, 7z, or bsdtar to extract ${file}" >&2
        echo "  Ubuntu: sudo apt install unrar-free   (or p7zip-full)" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown archive: ${file}" >&2
      exit 1
      ;;
  esac
}

copy_tree_into_csgo() {
  local src_root="$1"
  # Release may be csgo/..., or flat addons/...
  if [[ -d "${src_root}/csgo" ]]; then
    cp -a "${src_root}/csgo/." "${CSGO_ROOT}/"
    return 0
  fi
  if [[ -d "${src_root}/addons" ]]; then
    cp -a "${src_root}/addons/." "${CSGO_ROOT}/addons/"
    return 0
  fi
  # Search one level down (common zip layout)
  local sub
  for sub in "${src_root}"/*; do
    if [[ -d "${sub}/csgo" ]]; then
      cp -a "${sub}/csgo/." "${CSGO_ROOT}/"
      return 0
    fi
    if [[ -d "${sub}/addons" ]]; then
      cp -a "${sub}/addons/." "${CSGO_ROOT}/addons/"
      return 0
    fi
  done
  echo "WARN: could not find csgo/ or addons/ in extracted archive — copy files manually from ${src_root}"
  return 1
}

echo "=== CSGO_WeaponStickers installer ==="
echo "CSGO_ROOT=${CSGO_ROOT}"

echo ""
echo ">>> Download WeaponStickers v1.3.6 (z1ntex)"
curl -fsSL "${WEAPONSTICKERS_RAR_URL}" -o "${TMP_DIR}/weaponstickers.rar"
extract_archive "${TMP_DIR}/weaponstickers.rar" "${TMP_DIR}/stickers"
copy_tree_into_csgo "${TMP_DIR}/stickers" || true

echo ""
echo ">>> Download eItems 0.10 No API (if not bundled)"
if [[ ! -f "${SM}/plugins/eitems.smx" ]]; then
  curl -fsSL "${EITEMS_ZIP_URL}" -o "${TMP_DIR}/eitems.zip"
  extract_archive "${TMP_DIR}/eitems.zip" "${TMP_DIR}/eitems"
  copy_tree_into_csgo "${TMP_DIR}/eitems" || true
else
  echo "eitems.smx already present — skip download"
fi

echo ""
echo ">>> PTaH extension (required by eItems / stickers)"
if [[ ! -f "${SM}/extensions/PTaH.ext.so" && ! -f "${SM}/extensions/PTaH.ext.dll" ]]; then
  curl -fsSL "${PTAH_URL}" -o "${TMP_DIR}/ptah.zip"
  extract_archive "${TMP_DIR}/ptah.zip" "${TMP_DIR}/ptah"
  if [[ -d "${TMP_DIR}/ptah/addons" ]]; then
    cp -a "${TMP_DIR}/ptah/addons/." "${CSGO_ROOT}/addons/"
  else
    find "${TMP_DIR}/ptah" -name 'PTaH.ext.*' -exec cp -a {} "${SM}/extensions/" \; 2>/dev/null || true
  fi
else
  echo "PTaH extension already present"
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
echo "api-csgo writes same file when WEAPONS_DB_PATH points to sourcemod-local.sq3 dir"

echo ""
echo "=== Plugin files ==="
ls -la "${SM}/plugins/csgo_weaponstickers.smx" 2>/dev/null || ls -la "${SM}/plugins/"*weaponstickers*.smx 2>/dev/null || echo "WARN: csgo_weaponstickers.smx not found — check extract"
ls -la "${SM}/plugins/eitems.smx" 2>/dev/null || echo "WARN: eitems.smx not found"

echo ""
echo "=== Done ==="
echo "Restart srcds OR in screen:"
echo "  sm plugins load eitems"
echo "  sm plugins load csgo_weaponstickers"
echo ""
echo "Verify:"
echo "  sm plugins list | grep -iE 'eitems|weaponstickers'"
echo ""
echo "api-csgo: git pull && npm run build && npm run pm2:restart"
echo "Test route:"
echo "  curl -s -X POST http://127.0.0.1:\${PORT:-3000}/api/csgo/stickers/player-sync \\"
echo "    -H 'x-skins-sync-key: \$CSGO_SKINS_SYNC_KEY' -H 'Content-Type: application/json' \\"
echo "    -d '{\"steamId\":\"STEAM_1:0:0\",\"entries\":[]}'"
