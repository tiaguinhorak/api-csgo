#!/usr/bin/env bash
set -euo pipefail

# CS:GO scoreboard "SITE DO SERVIDOR" uses motd.txt in the csgo folder (not host_url / sv_motd).
#
# Usage:
#   cd ~/api-csgo && ./scripts/ensure-clutch-server-branding.sh
#
# Requires CLUTCH_SITE_URL in .env (default https://clutchclube.com.br).
# After updating motd.txt: restart srcds or change map (motd is read at map load).

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
  echo "srcds is running from ${LIVE_ROOT} (not default ${CSGO_ROOT}) — writing motd there."
  CSGO_ROOT="${LIVE_ROOT}"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SITE_URL="${CLUTCH_SITE_URL:-https://clutchclube.com.br}"
SITE_URL="${SITE_URL%/}"
MARKER="clutch_server_branding"
CFG_NAME="clutch_server_branding.cfg"
CFG_PATH="${CSGO_ROOT}/cfg/${CFG_NAME}"
SERVER_CFG="${CSGO_ROOT}/cfg/server.cfg"
MOTD_FILE="${CSGO_ROOT}/motd.txt"
CFG_TEMPLATE="${REPO_ROOT}/sourcemod/clutch_server_branding.cfg"

if [[ ! -d "${CSGO_ROOT}/cfg" ]]; then
  echo "CSGO cfg dir not found: ${CSGO_ROOT}/cfg" >&2
  echo "Set CSGO_ROOT to your live csgo directory." >&2
  exit 1
fi

if [[ -f "${CFG_TEMPLATE}" ]]; then
  cp -f "${CFG_TEMPLATE}" "${CFG_PATH}"
else
  cat > "${CFG_PATH}" <<EOF
// ${MARKER}
motdfile "motd.txt"
EOF
fi

printf '%s\n' "${SITE_URL}" > "${MOTD_FILE}"

echo "Wrote ${MOTD_FILE}:"
cat "${MOTD_FILE}"
echo ""
echo "Wrote ${CFG_PATH}"

if [[ -f "${SERVER_CFG}" ]]; then
  if grep -q "${MARKER}" "${SERVER_CFG}" || grep -q "exec ${CFG_NAME}" "${SERVER_CFG}"; then
    echo "server.cfg already execs ${CFG_NAME}"
  else
    {
      echo ""
      echo "// ${MARKER}"
      echo "exec ${CFG_NAME}"
    } >> "${SERVER_CFG}"
    echo "Appended exec ${CFG_NAME} to ${SERVER_CFG}"
  fi
else
  echo "WARN: ${SERVER_CFG} not found — add manually: exec ${CFG_NAME}"
fi

echo ""
echo "CS:GO does NOT have host_url / sv_motd — scoreboard link comes from motd.txt."
echo "Apply: restart srcds or change map, then check scoreboard button."
echo "Optional console (may work on some builds): motdfile motd.txt"
