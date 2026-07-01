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

# Site on same VPS often listens on :3000 while :80 is closed/hairpin-blocked.
set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a
parse_clutch_site_url "${CLUTCH_SITE_URL:-${PROD_URL}}"
SITE_ON_3000=""
if SITE_ON_3000="$(clutch_probe_nextjs_base_url "${SITE_HOST}" 3000)"; then
  echo ""
  echo "Detected Next.js at ${SITE_ON_3000} (port 80 may be unavailable from this VPS)."
  if [[ "${CLUTCH_SITE_URL:-}" != "${SITE_ON_3000}" ]]; then
    set_kv "CLUTCH_SITE_URL" "${SITE_ON_3000}"
    set_kv "SITE_ORIGIN" "${SITE_ON_3000}"
  fi
  if [[ "${CLUTCH_SITE_INTERNAL_URL:-}" != "${SITE_ON_3000}" ]]; then
    set_kv "CLUTCH_SITE_INTERNAL_URL" "${SITE_ON_3000}"
  fi
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
echo "--- Co-located site (same VPS) ---"
INTERNAL_SET=0
if [[ -n "${SITE_ON_3000:-}" ]]; then
  echo "OK: using ${SITE_ON_3000} for api-csgo → site (127.0.0.1:3000 may be api-csgo, not Next.js)."
  INTERNAL_SET=1
else
  for port in 3000 3002; do
    health="$(curl -4 -sf -m 3 "http://127.0.0.1:${port}/api/health" 2>/dev/null || true)"
    if clutch_is_nextjs_health_json "${health}"; then
      internal_url="http://127.0.0.1:${port}"
      if [[ "${CLUTCH_SITE_INTERNAL_URL:-}" != "${internal_url}" ]]; then
        set_kv "CLUTCH_SITE_INTERNAL_URL" "${internal_url}"
      else
        echo "OK: CLUTCH_SITE_INTERNAL_URL=${internal_url}"
      fi
      INTERNAL_SET=1
      echo "Next.js on loopback — api-csgo will use internal URL."
      break
    fi
  done
fi

if [[ "${INTERNAL_SET}" -eq 0 ]]; then
  echo "No Next.js detected on :3000 — site may be on another host."
  echo "Public CLUTCH_SITE_URL must be reachable OR deploy site on this VPS."
fi

echo ""
echo "Restart API: pm2 restart api-csgo --update-env"
echo "Test DNS:    bash scripts/check-site-dns.sh"
echo "When site is live: bash scripts/sync-stickers-from-site.sh"
echo "Until then:        on dev PC → bash scripts/push-stickers-dev-to-vps.sh"
