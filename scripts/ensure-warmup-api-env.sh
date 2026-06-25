#!/usr/bin/env bash
# Minimum .env for warmup VPS api-csgo (pm2 + site player-sync).
# Ranked VPS: never adds WARMUP_VPS=1 or LAN URL fallback.
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

set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

# shellcheck source=lib/parse-site-url.sh
source "${REPO_ROOT}/scripts/lib/parse-site-url.sh"

set_kv_if_missing "PORT" "3001"
set_kv_if_missing "BIND_HOST" "0.0.0.0"

if clutch_is_warmup_pool; then
  set_kv_if_missing "WARMUP_VPS" "1"
  set_kv_if_missing "CLUTCH_CS_SCREEN" "csgo-warmup-#1"
  set_kv_if_missing "CSGO_RCON_LOOPBACK" "1"
  set_kv_if_missing "CSGO_SERVER_HOST" "127.0.0.1"
  set_kv_if_missing "CSGO_RCON_PORT" "27015"
  set_kv_if_missing "CLUTCH_SITE_FALLBACK_URL" "http://192.168.100.6:3000"
else
  echo "Ranked/public VPS — skip WARMUP_VPS and LAN fallback (use fix-ranked-site-url.sh)"
fi

if grep -qE '^BIND_HOST=127' "${ENV_FILE}"; then
  sed -i 's/^BIND_HOST=.*/BIND_HOST=0.0.0.0/' "${ENV_FILE}"
  echo "Fixed BIND_HOST=0.0.0.0 (required for site LAN push)"
fi

bash "${REPO_ROOT}/scripts/ensure-clutch-site-env.sh"

fix_warmup_site_url_if_dns_broken() {
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a

  local site_url="${CLUTCH_SITE_URL:-https://clutchclube.com.br}"
  local fallback="${CLUTCH_SITE_FALLBACK_URL:-http://192.168.100.6:3000}"
  parse_clutch_site_url "${site_url}"

  if clutch_site_host_is_private_lan "${SITE_HOST}"; then
    if clutch_is_warmup_pool; then
      echo "WARN: CLUTCH_SITE_URL is LAN — warmup-only"
    else
      echo "WARN: CLUTCH_SITE_URL is LAN — run: bash scripts/fix-ranked-site-url.sh"
    fi
    return 0
  fi

  if clutch_site_host_is_ip "${SITE_HOST}"; then
    return 0
  fi

  if getent hosts "${SITE_HOST}" >/dev/null 2>&1; then
    return 0
  fi

  echo "WARN: VPS cannot resolve ${SITE_HOST} (system DNS broken)"

  RESOLVED_SITE_IP=""
  if clutch_resolve_site_ip "${SITE_HOST}"; then
    if ! grep -qE "^CLUTCH_SITE_RESOLVE_IP=${RESOLVED_SITE_IP}" "${ENV_FILE}"; then
      if grep -qE '^CLUTCH_SITE_RESOLVE_IP=' "${ENV_FILE}"; then
        sed -i "s|^CLUTCH_SITE_RESOLVE_IP=.*|CLUTCH_SITE_RESOLVE_IP=${RESOLVED_SITE_IP}|" "${ENV_FILE}"
      else
        echo "CLUTCH_SITE_RESOLVE_IP=${RESOLVED_SITE_IP}" >> "${ENV_FILE}"
      fi
      echo "Set CLUTCH_SITE_RESOLVE_IP=${RESOLVED_SITE_IP} (public DNS lookup)"
    fi
    return 0
  fi

  if clutch_is_warmup_pool; then
    echo "WARN: public DNS lookup failed — switching CLUTCH_SITE_URL to LAN fallback ${fallback}"
    if grep -qE '^CLUTCH_SITE_URL=' "${ENV_FILE}"; then
      sed -i "s|^CLUTCH_SITE_URL=.*|CLUTCH_SITE_URL=${fallback}|" "${ENV_FILE}"
    else
      echo "CLUTCH_SITE_URL=${fallback}" >> "${ENV_FILE}"
    fi
    if grep -qE '^SITE_ORIGIN=' "${ENV_FILE}"; then
      sed -i "s|^SITE_ORIGIN=.*|SITE_ORIGIN=${fallback}|" "${ENV_FILE}"
    fi
    echo "Updated .env — restart api-csgo: npm run pm2:restart"
  else
    echo "WARN: site DNS not ready — keeping production URL (ranked VPS cannot use LAN dev PC)."
    echo "      Push from dev PC: bash scripts/push-stickers-dev-to-vps.sh"
  fi
}

fix_warmup_site_url_if_dns_broken

if ! clutch_is_warmup_pool; then
  bash "${REPO_ROOT}/scripts/fix-ranked-site-url.sh" || true
fi

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

echo "OK: api .env checked ($(grep -c '^' "${ENV_FILE}") lines)"

bash "${REPO_ROOT}/scripts/pm2-local.sh" >/dev/null
echo "OK: pm2 available ($(command -v pm2))"

echo ""
bash "${REPO_ROOT}/scripts/verify-warmup-api-lan.sh" || true
