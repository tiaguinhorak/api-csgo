#!/usr/bin/env bash
# Bootstrap .env from SERVER_PROFILE (ranked vs public modes).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
EXAMPLE="${REPO_ROOT}/.env.example"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${EXAMPLE}" ]]; then
    cp "${EXAMPLE}" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from .env.example — edit SERVER_PROFILE and secrets, then re-run deploy."
  else
    echo "ERROR: ${ENV_FILE} missing" >&2
    exit 1
  fi
fi

env_repair_unquoted_values "${ENV_FILE}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/profile.sh"
clutch_profile_init "${REPO_ROOT}"

env_set_kv_if_missing "${ENV_FILE}" "PORT" "3001"
env_set_kv_if_missing "${ENV_FILE}" "DATA_DIR" "./data"
env_set_kv_if_missing "${ENV_FILE}" "CSGO_RCON_LOOPBACK" "1"
env_set_kv_if_missing "${ENV_FILE}" "CSGO_SERVER_HOST" "127.0.0.1"
env_set_kv_if_missing "${ENV_FILE}" "CSGO_RCON_PORT" "27015"
env_set_kv_if_missing "${ENV_FILE}" "CSGO_SERVER_DIR" "/home/csgo/server"
env_set_kv_if_missing "${ENV_FILE}" "SERVER_PROFILE" "${CLUTCH_SERVER_PROFILE}"
env_set_kv_if_missing "${ENV_FILE}" "CSGO_SERVER_POOL" "${CLUTCH_SERVER_POOL}"

if [[ "${CLUTCH_IS_RANKED}" -eq 1 ]]; then
  env_set_kv_if_missing "${ENV_FILE}" "CLUTCH_CS_SCREEN" "csgo-clutch-#1"
else
  env_set_kv_if_missing "${ENV_FILE}" "WARMUP_VPS" "1"
  env_set_kv_if_missing "${ENV_FILE}" "CLUTCH_CS_SCREEN" "csgo-warmup-#1"
  env_set_kv_if_missing "${ENV_FILE}" "CSGO_BIND_IP" "0.0.0.0"
  env_set_kv_if_missing "${ENV_FILE}" "BIND_HOST" "0.0.0.0"
  if ! grep -qE '^CSGO_PUBLIC_HOST=' "${ENV_FILE}"; then
    echo "WARN: add CSGO_PUBLIC_HOST=<public IP> so players outside LAN can connect"
  fi
  if grep -qE '^BIND_HOST=127' "${ENV_FILE}"; then
    sed -i 's/^BIND_HOST=.*/BIND_HOST=0.0.0.0/' "${ENV_FILE}"
    echo "Fixed BIND_HOST=0.0.0.0 (site LAN push)"
  fi
fi

env_set_kv_if_missing "${ENV_FILE}" "SERVER_MODE_LABEL" "${CLUTCH_SERVER_MODE_LABEL}"
env_set_kv_if_missing "${ENV_FILE}" "SERVER_NAME" "${CLUTCH_SERVER_NAME}"

bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"

if ! grep -qE '^CSGO_SKINS_SYNC_KEY=' "${ENV_FILE}"; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY missing (must match site/.env)" >&2
  exit 1
fi

echo "OK: profile env — $(grep '^SERVER_PROFILE=' "${ENV_FILE}" || echo 'SERVER_PROFILE=?')"

if [[ "${CLUTCH_IS_RANKED}" -eq 0 ]]; then
  bash "${REPO_ROOT}/scripts/pm2-local.sh" >/dev/null 2>&1 || true
fi
