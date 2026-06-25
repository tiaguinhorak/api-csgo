#!/usr/bin/env bash
# Ranked / public VPS: production site URL, no LAN fallback, WARMUP_VPS=0.
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

set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

echo "=== Fix ranked VPS .env ==="

# Ranked pool flags — prevent warmup scripts from reverting URL to LAN.
if [[ "${WARMUP_VPS:-0}" != "0" ]]; then
  set_kv "WARMUP_VPS" "0"
fi

if [[ "${CSGO_SERVER_POOL:-}" == "warmup" ]]; then
  set_kv "CSGO_SERVER_POOL" "ranked"
fi

if grep -qE '^CLUTCH_SITE_FALLBACK_URL=' "${ENV_FILE}"; then
  sed -i 's/^CLUTCH_SITE_FALLBACK_URL=/#CLUTCH_SITE_FALLBACK_URL=/' "${ENV_FILE}"
  echo "Commented CLUTCH_SITE_FALLBACK_URL (LAN — ranked VPS cannot reach dev PC)"
fi

CURRENT="${CLUTCH_SITE_URL:-${SITE_ORIGIN:-}}"
parse_clutch_site_url "${CURRENT:-http://invalid}"

needs_url_fix=0
if [[ -z "${CURRENT}" ]]; then
  needs_url_fix=1
elif clutch_site_host_is_private_lan "${SITE_HOST}"; then
  needs_url_fix=1
fi

if [[ "${needs_url_fix}" -eq 1 ]]; then
  echo "Current CLUTCH_SITE_URL=${CURRENT}"
  echo "LAN/localhost URLs only work when site runs on your PC on the same network."
  echo "Ranked VPS must use production: ${PROD_URL}"
  echo ""
  set_kv "CLUTCH_SITE_URL" "${PROD_URL}"
  set_kv "SITE_ORIGIN" "${PROD_URL}"
else
  echo "OK: CLUTCH_SITE_URL=${CURRENT} (public)"
fi

set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

parse_clutch_site_url "${CLUTCH_SITE_URL:-${PROD_URL}}"
RESOLVED_SITE_IP=""
if ! clutch_site_host_is_ip "${SITE_HOST}" && clutch_resolve_site_ip "${SITE_HOST}"; then
  set_kv "CLUTCH_SITE_RESOLVE_IP" "${RESOLVED_SITE_IP}"
elif ! clutch_site_host_is_ip "${SITE_HOST}"; then
  echo ""
  echo "WARN: cannot resolve ${SITE_HOST} yet (site may not be live on Hostinger)."
  echo "      Keep production URL — do NOT switch to LAN."
  echo "      Until site is live, push stickers from your PC:"
  echo "        bash scripts/push-stickers-dev-to-vps.sh"
fi

echo ""
echo "Restart API: npm run pm2:restart"
echo "Test DNS:    bash scripts/check-site-dns.sh"
echo "When site is live: bash scripts/sync-stickers-from-site.sh"
echo "Until then:        on dev PC → bash scripts/push-stickers-dev-to-vps.sh"
