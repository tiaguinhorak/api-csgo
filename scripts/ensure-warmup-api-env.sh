#!/usr/bin/env bash
# Minimum .env for warmup VPS api-csgo (pm2 + site player-sync).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
EXAMPLE="${REPO_ROOT}/.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${EXAMPLE}" ]]; then
    cp "${EXAMPLE}" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from .env.example — review values before deploy."
  else
    echo "ERROR: ${ENV_FILE} missing and no .env.example" >&2
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

set_kv_if_missing "PORT" "3001"
set_kv_if_missing "WARMUP_VPS" "1"
set_kv_if_missing "CLUTCH_CS_SCREEN" "csgo-warmup-#1"
set_kv_if_missing "CSGO_RCON_LOOPBACK" "1"
set_kv_if_missing "CSGO_SERVER_HOST" "127.0.0.1"
set_kv_if_missing "CSGO_RCON_PORT" "27015"
set_kv_if_missing "BIND_HOST" "0.0.0.0"

if grep -qE '^BIND_HOST=127' "${ENV_FILE}"; then
  sed -i 's/^BIND_HOST=.*/BIND_HOST=0.0.0.0/' "${ENV_FILE}"
  echo "Fixed BIND_HOST=0.0.0.0 (required for site LAN push)"
fi

bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"

set_kv_if_missing "CLUTCH_SITE_FALLBACK_URL" "http://192.168.100.6:3000"

if ! grep -qE '^CSGO_SKINS_SYNC_KEY=' "${ENV_FILE}"; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY missing in .env (must match site/.env)" >&2
  exit 1
fi

if ! grep -qE '^API_KEY=' "${ENV_FILE}" && ! grep -qE '^CSGO_API_KEY=' "${ENV_FILE}"; then
  echo "WARN: API_KEY / CSGO_API_KEY missing — CSGO_SKINS_SYNC_KEY is enough for player-sync."
  echo "      Add API_KEY=suachaveapi (same as site CSGO_API_KEY) if you use admin API routes."
fi

if ! grep -qE '^CSGO_RCON_PASSWORD=' "${ENV_FILE}"; then
  echo "WARN: CSGO_RCON_PASSWORD missing — equip won't stage sm_clutch_applyskins via RCON."
fi

echo "OK: warmup api .env checked ($(grep -c '^' "${ENV_FILE}") lines)"

bash "${REPO_ROOT}/scripts/pm2-local.sh" >/dev/null
echo "OK: pm2 available ($(command -v pm2))"

echo ""
bash "${REPO_ROOT}/scripts/verify-warmup-api-lan.sh" || true
