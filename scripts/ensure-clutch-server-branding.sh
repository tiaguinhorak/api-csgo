#!/usr/bin/env bash
set -euo pipefail

# Sets host_url / sv_motd so scoreboard "SITE DO SERVIDOR" opens Clutch site (not Valve MOTD).
#
# Usage:
#   cd ~/api-csgo && ./scripts/ensure-clutch-server-branding.sh
#
# Requires CLUTCH_SITE_URL in .env (default https://clutchclube.com.br).
# After first run, restart srcds or: host_url <url>; sv_motd <url>

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

if [[ ! -d "${CSGO_ROOT}/cfg" ]]; then
  echo "CSGO cfg dir not found: ${CSGO_ROOT}/cfg" >&2
  echo "Set CSGO_ROOT to your live csgo directory." >&2
  exit 1
fi

cat > "${CFG_PATH}" <<EOF
// ${MARKER} — do not edit by hand; use ensure-clutch-server-branding.sh
host_url "${SITE_URL}"
sv_motd "${SITE_URL}"
EOF

echo "Wrote ${CFG_PATH}"
echo "  host_url / sv_motd → ${SITE_URL}"

printf '%s\n' "${SITE_URL}" > "${MOTD_FILE}"
echo "Wrote ${MOTD_FILE}"

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
echo "Apply now (in srcds console) or restart server:"
echo "  host_url \"${SITE_URL}\""
echo "  sv_motd \"${SITE_URL}\""
