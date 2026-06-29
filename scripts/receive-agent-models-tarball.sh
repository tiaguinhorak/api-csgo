#!/usr/bin/env bash
set -euo pipefail

# Unpack agent models tarball from a PC (models + materials from VPK extract).
#
# PC: python scripts/extract-agent-models-from-csgo.py
#     scp /tmp/custom_player.tgz csgo@server:/tmp/
# VPS: ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
TARBALL="${1:-/tmp/custom_player.tgz}"

if [[ ! -f "${TARBALL}" ]]; then
  echo "ERROR: tarball not found: ${TARBALL}" >&2
  echo ""
  echo "On your PC (api-csgo repo):" >&2
  echo "  python scripts/extract-agent-models-from-csgo.py" >&2
  echo "  scp \$TMP/custom_player.tgz csgo@YOUR_VPS:/tmp/" >&2
  echo "Or one-shot: VPS_HOST=csgo@YOUR_VPS ./scripts/push-agent-models-from-pc.sh" >&2
  exit 1
fi

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "ERROR: stop srcds before replacing models (screen -r → stop server)" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo ">>> Extracting ${TARBALL}"
tar xzf "${TARBALL}" -C "${STAGING}"

if [[ -d "${STAGING}/models/player/custom_player" ]]; then
  mkdir -p "${CSGO_ROOT}/models/player"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${STAGING}/models/player/custom_player/" "${CSGO_ROOT}/models/player/custom_player/"
  else
    rm -rf "${CSGO_ROOT}/models/player/custom_player"
    cp -a "${STAGING}/models/player/custom_player" "${CSGO_ROOT}/models/player/"
  fi
elif [[ -d "${STAGING}/custom_player" ]]; then
  mkdir -p "${CSGO_ROOT}/models/player"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${STAGING}/custom_player/" "${CSGO_ROOT}/models/player/custom_player/"
  else
    rm -rf "${CSGO_ROOT}/models/player/custom_player"
    cp -a "${STAGING}/custom_player" "${CSGO_ROOT}/models/player/"
  fi
else
  echo "ERROR: tarball missing models/player/custom_player or custom_player/" >&2
  find "${STAGING}" -maxdepth 3 -type d >&2
  exit 1
fi

if [[ -d "${STAGING}/materials/models/player/custom_player" ]]; then
  mkdir -p "${CSGO_ROOT}/materials/models/player"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${STAGING}/materials/models/player/custom_player/" \
      "${CSGO_ROOT}/materials/models/player/custom_player/"
  else
    rm -rf "${CSGO_ROOT}/materials/models/player/custom_player"
    cp -a "${STAGING}/materials/models/player/custom_player" \
      "${CSGO_ROOT}/materials/models/player/"
  fi
fi

if [[ -n "${CSGO_FASTDL_ROOT:-}" ]]; then
  echo ">>> Mirroring to fastdl ${CSGO_FASTDL_ROOT}"
  mkdir -p "${CSGO_FASTDL_ROOT}/models/player" "${CSGO_FASTDL_ROOT}/materials/models/player"
  rsync -a "${CSGO_ROOT}/models/player/custom_player/" \
    "${CSGO_FASTDL_ROOT}/models/player/custom_player/" 2>/dev/null || true
  if [[ -d "${CSGO_ROOT}/materials/models/player/custom_player" ]]; then
    rsync -a "${CSGO_ROOT}/materials/models/player/custom_player/" \
      "${CSGO_FASTDL_ROOT}/materials/models/player/custom_player/" 2>/dev/null || true
  fi
fi

count="$(find "${CSGO_ROOT}/models/player/custom_player" -name '*.mdl' 2>/dev/null | wc -l | tr -d ' ')"
echo "OK: ${count} .mdl files in ${CSGO_ROOT}/models/player/custom_player"
echo "Run: ./scripts/verify-agent-models.sh"
