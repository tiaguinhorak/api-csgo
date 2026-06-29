#!/usr/bin/env bash
set -euo pipefail

# Install CS:GO agent player models (models/player/custom_player/).
#
# Steam app 740 (dedicated server) does NOT ship these files.
# SteamCMD app 730 (CS:GO client) usually fails on Linux (0x202 / no subscription).
# Use push from PC instead:
#   VPS_HOST=csgo@YOUR_VPS ./scripts/push-agent-models-from-pc.sh
#
# Or manual tarball:
#   scp custom_player.tgz csgo@server:/tmp/
#   ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz

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
MIN_FREE_MB="${MIN_FREE_MB:-2048}"

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

check_disk_space() {
  local dest_parent
  dest_parent="$(dirname "${DEST}")"
  mkdir -p "${dest_parent}"
  local avail_kb
  avail_kb="$(df -Pk "${dest_parent}" | awk 'NR==2 {print $4}')"
  local avail_mb=$((avail_kb / 1024))
  echo "Disk free on ${dest_parent}: ${avail_mb} MB"
  if [[ "${avail_mb}" -lt "${MIN_FREE_MB}" ]]; then
    echo "ERROR: need at least ${MIN_FREE_MB} MB free (custom_player is ~500MB–2GB)." >&2
    df -h "${dest_parent}" >&2
    exit 1
  fi
}

steamcmd_failed_hint() {
  local code="$1"
  echo ""
  echo "SteamCMD failed (exit ${code}). Common causes:" >&2
  echo "  • 0x202 = disk full or write failure — run: df -h" >&2
  echo "  • app 730 not available on Linux SteamCMD (CS:GO client is Windows-only now)" >&2
  echo ""
  echo "Use copy from your gaming PC instead:" >&2
  echo "  VPS_HOST=csgo@YOUR_VPS ./scripts/push-agent-models-from-pc.sh" >&2
  echo "Or tarball:" >&2
  echo "  scp custom_player.tgz ${VPS_HOST:-csgo@server}:/tmp/" >&2
  echo "  ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz" >&2
}

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "ERROR: srcds_linux is running — stop the server first (screen -r)." >&2
  exit 1
fi

echo "=== Install agent models (custom_player) ==="
echo "Server:  ${DEST}"
echo ""
check_disk_space

SRC=""
if [[ -n "${CSGO_CLIENT_CSGO:-}" ]]; then
  SRC="$(find_client_custom_player "${CSGO_CLIENT_CSGO}" || true)"
  if [[ -z "${SRC}" ]]; then
    echo "ERROR: CSGO_CLIENT_CSGO=${CSGO_CLIENT_CSGO} has no models/player/custom_player" >&2
    exit 1
  fi
  echo "Using local path: ${SRC}"
elif [[ -f /tmp/custom_player.tgz ]]; then
  echo "Found /tmp/custom_player.tgz — extracting"
  "${REPO_ROOT}/scripts/receive-agent-models-tarball.sh" /tmp/custom_player.tgz
  mirror_fastdl
  exit 0
else
  SRC="$(find_client_custom_player "${CLIENT_INSTALL}" || true)"
  if [[ -z "${SRC}" ]]; then
    if [[ ! -x "${STEAMCMD}" ]]; then
      echo "ERROR: steamcmd not found and no local custom_player folder." >&2
      steamcmd_failed_hint 1
      exit 1
    fi
    if [[ "${ALLOW_STEAMCMD_730:-0}" != "1" ]]; then
      echo "SteamCMD app 730 (CS:GO client) usually cannot be installed on Linux." >&2
      echo "Copy from a PC with CS:GO / CS:GO Legacy in Steam:" >&2
      echo ""
      echo "  On PC (Git Bash): VPS_HOST=csgo@19520 ./scripts/push-agent-models-from-pc.sh" >&2
      echo "  On VPS after scp:  ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz" >&2
      echo ""
      echo "To force SteamCMD attempt anyway: ALLOW_STEAMCMD_730=1 ./scripts/install-agent-models.sh" >&2
      exit 1
    fi
    echo "Trying SteamCMD app 730 (often fails on Linux) → ${CLIENT_INSTALL}"
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
      steamcmd_failed_hint "${STEAM_EXIT}"
      exit 1
    fi
    SRC="$(find_client_custom_player "${CLIENT_INSTALL}" || true)"
    if [[ -z "${SRC}" ]]; then
      echo "ERROR: app 730 finished but custom_player not found under ${CLIENT_INSTALL}" >&2
      ls -la "${CLIENT_INSTALL}" >&2 || true
      exit 1
    fi
    echo "Found after download: ${SRC}"
  else
    echo "Using cached staging: ${SRC}"
  fi
fi

copy_tree "${SRC}"
mirror_fastdl

count="$(find "${DEST}" -name '*.mdl' 2>/dev/null | wc -l | tr -d ' ')"
echo ""
echo "OK: ${count} .mdl files in ${DEST}"
echo "Run: ./scripts/verify-agent-models.sh"
