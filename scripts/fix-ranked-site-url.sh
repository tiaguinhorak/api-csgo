#!/usr/bin/env bash
# Ranked / public VPS cannot use CLUTCH_SITE_URL=http://192.168.x.x:3000 (LAN dev PC).
# Resets to production Hostinger URL and optional CLUTCH_SITE_RESOLVE_IP.
#
# Usage: cd ~/api-csgo && bash scripts/fix-ranked-site-url.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# shellcheck source=lib/parse-site-url.sh
source "${REPO_ROOT}/scripts/lib/parse-site-url.sh"

PROD_URL="${CLUTCH_PRODUCTION_SITE_URL:-https://clutchclube.com.br}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} missing" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

CURRENT="${CLUTCH_SITE_URL:-${SITE_ORIGIN:-}}"
parse_clutch_site_url "${CURRENT:-http://invalid}"

needs_fix=0
if [[ -z "${CURRENT}" ]]; then
  needs_fix=1
elif clutch_site_host_is_private_lan "${SITE_HOST}"; then
  needs_fix=1
fi

if [[ "${needs_fix}" -eq 0 ]]; then
  echo "OK: CLUTCH_SITE_URL=${CURRENT} (public — no change)"
  exit 0
fi

echo "=== Fix ranked site URL ==="
echo "Current CLUTCH_SITE_URL=${CURRENT}"
echo "LAN/localhost URLs only work when site runs on your PC on the same network."
echo "Ranked VPS must use production: ${PROD_URL}"
echo ""

set_kv() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    echo "${key}=${value}" >> "${ENV_FILE}"
  fi
  echo "Set ${key}=${value}"
}

set_kv "CLUTCH_SITE_URL" "${PROD_URL}"
set_kv "SITE_ORIGIN" "${PROD_URL}"

if grep -qE '^CLUTCH_SITE_FALLBACK_URL=http://192\.168\.' "${ENV_FILE}"; then
  sed -i 's/^CLUTCH_SITE_FALLBACK_URL=/#CLUTCH_SITE_FALLBACK_URL=/' "${ENV_FILE}"
  echo "Commented CLUTCH_SITE_FALLBACK_URL (LAN — not used on ranked VPS)"
fi

parse_clutch_site_url "${PROD_URL}"
RESOLVED_SITE_IP=""
if ! clutch_site_host_is_ip "${SITE_HOST}" && clutch_resolve_site_ip "${SITE_HOST}"; then
  set_kv "CLUTCH_SITE_RESOLVE_IP" "${RESOLVED_SITE_IP}"
fi

echo ""
echo "Restart API: npm run pm2:restart"
echo "Test: bash scripts/check-site-dns.sh"
echo "Sync: bash scripts/sync-stickers-from-site.sh"
