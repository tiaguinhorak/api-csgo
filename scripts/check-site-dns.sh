#!/usr/bin/env bash
# Verifica se a VPS alcança o site (produção ou dev local http://192.168.x.x:3000).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/parse-site-url.sh
source "${REPO_ROOT}/scripts/lib/parse-site-url.sh"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SITE="${CLUTCH_SITE_URL:-https://clutchclube.com.br}"
parse_clutch_site_url "${SITE}"

echo "=== Site reachability ==="
echo "CLUTCH_SITE_URL=${SITE}"
echo "host=${SITE_HOST} port=${SITE_PORT} scheme=${SITE_SCHEME}"
if [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]]; then
  echo "CLUTCH_SITE_RESOLVE_IP=${CLUTCH_SITE_RESOLVE_IP}"
fi
echo ""

if clutch_site_host_is_ip "${SITE_HOST}"; then
  echo "(IP literal — skipping DNS lookup)"
  echo ""
else
  if command -v getent >/dev/null 2>&1; then
    echo "--- getent hosts ${SITE_HOST} ---"
    getent hosts "${SITE_HOST}" || echo "FAIL: cannot resolve ${SITE_HOST}"
    echo ""
  fi
  if command -v host >/dev/null 2>&1; then
    echo "--- host ${SITE_HOST} ---"
    host "${SITE_HOST}" || true
    echo ""
  fi
fi

CURL_OPTS=( -fsSL --max-time 8 -o /dev/null -w "HTTP %{http_code}\n" )
if should_use_site_resolve; then
  CURL_OPTS+=( --resolve "${SITE_HOST}:${SITE_PORT}:${CLUTCH_SITE_RESOLVE_IP}" )
fi

echo "--- curl ${SITE}/ ---"
if curl "${CURL_OPTS[@]}" "${SITE}/"; then
  echo "OK: site responds"
else
  echo "FAIL: cannot reach ${SITE}"
  echo ""
  if clutch_site_host_is_ip "${SITE_HOST}"; then
    echo "Local dev checklist:"
    echo "  1) On your PC: cd site && npm run dev"
    echo "  2) Windows firewall: allow inbound TCP ${SITE_PORT}"
    echo "  3) Same LAN: VPS must reach ${SITE_HOST}:${SITE_PORT}"
    echo "  4) Remove CLUTCH_SITE_RESOLVE_IP from .env (only for https + domain)"
    if clutch_site_host_is_private_lan "${SITE_HOST}"; then
      echo ""
      echo "Ranked/public game VPS cannot use LAN URL — run:"
      echo "  bash scripts/fix-ranked-site-url.sh"
      echo "  npm run pm2:restart"
    fi
  else
  echo "Production checklist:"
  echo "  - Domain DNS must resolve (or set CLUTCH_SITE_RESOLVE_IP for https)"
  echo "  - Site not live yet? Push from dev PC:"
  echo "      bash scripts/push-stickers-dev-to-vps.sh"
  fi
  echo ""
  echo "Test without sync: sm_cvar clutch_platform_gate_enabled 0  (server console)"
  exit 1
fi

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo ""
  echo "--- steam-allowlist API ---"
  API_CURL=( -fsSL --max-time 10 -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" )
  if should_use_site_resolve; then
    API_CURL+=( --resolve "${SITE_HOST}:${SITE_PORT}:${CLUTCH_SITE_RESOLVE_IP}" )
  fi
  curl "${API_CURL[@]}" "${SITE%/}/api/csgo/steam-allowlist" | head -c 400
  echo ""
fi
