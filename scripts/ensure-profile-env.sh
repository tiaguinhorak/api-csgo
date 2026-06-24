#!/usr/bin/env bash
# Bootstrap .env from SERVER_PROFILE (ranked vs public modes).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
EXAMPLE="${REPO_ROOT}/.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${EXAMPLE}" ]]; then
    cp "${EXAMPLE}" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from .env.example — edit SERVER_PROFILE and secrets, then re-run deploy."
  else
    echo "ERROR: ${ENV_FILE} missing" >&2
    exit 1
  fi
fi

set_kv_if_missing() {
  local key="$1"
  local value="$2"
  if ! grep -qE "^${key}=" "${ENV_FILE}"; then
    echo "${key}=${value}" >> "${ENV_FILE}"
    echo "Added ${key}=${value}"
  fi
}

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/profile.sh"
clutch_profile_init "${REPO_ROOT}"

set_kv_if_missing "PORT" "3001"
set_kv_if_missing "DATA_DIR" "./data"
set_kv_if_missing "CSGO_RCON_LOOPBACK" "1"
set_kv_if_missing "CSGO_SERVER_HOST" "127.0.0.1"
set_kv_if_missing "CSGO_RCON_PORT" "27015"
set_kv_if_missing "CSGO_SERVER_DIR" "/home/csgo/server"
set_kv_if_missing "SERVER_PROFILE" "${CLUTCH_SERVER_PROFILE}"
set_kv_if_missing "CSGO_SERVER_POOL" "${CLUTCH_SERVER_POOL}"

if [[ "${CLUTCH_IS_RANKED}" -eq 1 ]]; then
  set_kv_if_missing "CLUTCH_CS_SCREEN" "csgo-clutch-#1"
else
  set_kv_if_missing "WARMUP_VPS" "1"
  set_kv_if_missing "CLUTCH_CS_SCREEN" "csgo-warmup-#1"
  set_kv_if_missing "BIND_HOST" "0.0.0.0"
  if grep -qE '^BIND_HOST=127' "${ENV_FILE}"; then
    sed -i 's/^BIND_HOST=.*/BIND_HOST=0.0.0.0/' "${ENV_FILE}"
    echo "Fixed BIND_HOST=0.0.0.0 (site LAN push)"
  fi
fi

set_kv_if_missing "SERVER_MODE_LABEL" "${CLUTCH_SERVER_MODE_LABEL}"
set_kv_if_missing "SERVER_NAME" "${CLUTCH_SERVER_NAME}"

bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"

if ! grep -qE '^CSGO_SKINS_SYNC_KEY=' "${ENV_FILE}"; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY missing (must match site/.env)" >&2
  exit 1
fi

echo "OK: profile env — $(grep '^SERVER_PROFILE=' "${ENV_FILE}" || echo 'SERVER_PROFILE=?')"

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  bash "${REPO_ROOT}/scripts/pm2-local.sh" >/dev/null 2>&1 || true
fi
