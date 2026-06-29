#!/usr/bin/env bash
set -euo pipefail

# Unpack custom_player tarball uploaded from a PC (SteamCMD cannot download app 730 on Linux).
#
# On your PC (Git Bash), create the archive:
#   cd ".../csgo/models/player"
#   tar czf /tmp/custom_player.tgz custom_player
#   scp /tmp/custom_player.tgz csgo@YOUR_VPS:/tmp/
#
# On VPS:
#   ./scripts/receive-agent-models-tarball.sh /tmp/custom_player.tgz

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
DEST_PARENT="${CSGO_ROOT}/models/player"
TARBALL="${1:-/tmp/custom_player.tgz}"

if [[ ! -f "${TARBALL}" ]]; then
  echo "ERROR: tarball not found: ${TARBALL}" >&2
  echo "Upload first: scp custom_player.tgz csgo@server:/tmp/" >&2
  exit 1
fi

if pgrep -x srcds_linux >/dev/null 2>&1; then
  echo "ERROR: stop srcds before replacing models (screen -r → stop server)" >&2
  exit 1
fi

mkdir -p "${DEST_PARENT}"
echo ">>> Extracting ${TARBALL} into ${DEST_PARENT}"
tar xzf "${TARBALL}" -C "${DEST_PARENT}"

if [[ ! -d "${DEST_PARENT}/custom_player" ]]; then
  echo "ERROR: expected ${DEST_PARENT}/custom_player after extract" >&2
  ls -la "${DEST_PARENT}" >&2
  exit 1
fi

count="$(find "${DEST_PARENT}/custom_player" -name '*.mdl' 2>/dev/null | wc -l | tr -d ' ')"
echo "OK: ${count} .mdl files in ${DEST_PARENT}/custom_player"
echo "Run: ./scripts/verify-agent-models.sh"
