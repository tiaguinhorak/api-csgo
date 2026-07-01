#!/usr/bin/env bash
# Verifica se a VPS alcança o site (produção, co-located loopback, ou dev LAN).
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
INTERNAL="${CLUTCH_SITE_INTERNAL_URL:-}"
parse_clutch_site_url "${SITE}"

echo "=== Site reachability ==="
echo "CLUTCH_SITE_URL=${SITE}"
echo "CLUTCH_SITE_INTERNAL_URL=${INTERNAL:-(not set)}"
echo "host=${SITE_HOST} port=${SITE_PORT} scheme=${SITE_SCHEME}"
if [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]]; then
  echo "CLUTCH_SITE_RESOLVE_IP=${CLUTCH_SITE_RESOLVE_IP}"
fi
echo ""

probe_url() {
  local label="$1"
  local url="$2"
  shift 2
  local code
  code="$(curl -4 -s -m 8 -o /dev/null -w "%{http_code}" "$@" "${url}" 2>/dev/null || echo "000")"
  echo "  ${label}: HTTP ${code} (${url})"
  [[ "${code}" =~ ^[23] ]]
}

probe_next_health() {
  local label="$1"
  local base="$2"
  base="${base%/}"
  local body code
  body="$(curl -4 -s -m 5 "${base}/api/health" 2>/dev/null || true)"
  if echo "${body}" | grep -q '"database"'; then
    echo "  ${label}: OK Next.js (${base}/api/health)"
    return 0
  fi
  code="$(curl -4 -s -m 5 -o /dev/null -w "%{http_code}" "${base}/api/health" 2>/dev/null || echo "000")"
  echo "  ${label}: HTTP ${code} — not Next.js or site down (${base})"
  return 1
}

if ! clutch_site_host_is_ip "${SITE_HOST}"; then
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
  echo "NOTE: curl uses -4 (IPv4). IPv6-only timeout is common on VPS hairpin."
  echo ""
fi

PUBLIC_OK=0
INTERNAL_OK=0

echo "--- Local / internal (same VPS) ---"
if [[ -n "${INTERNAL}" ]]; then
  if probe_next_health "CLUTCH_SITE_INTERNAL_URL" "${INTERNAL}"; then
    INTERNAL_OK=1
  fi
else
  echo "  (CLUTCH_SITE_INTERNAL_URL not set)"
fi

for port in 3000 3002; do
  if probe_next_health "127.0.0.1:${port}" "http://127.0.0.1:${port}"; then
    INTERNAL_OK=1
    if [[ -z "${INTERNAL}" ]]; then
      echo ""
      echo "  → Site Next.js detected locally. Add to .env:"
      echo "    CLUTCH_SITE_INTERNAL_URL=http://127.0.0.1:${port}"
      echo "    pm2 restart api-csgo --update-env"
    fi
    break
  fi
done

if probe_next_health "nginx loopback :80" "http://127.0.0.1"; then
  INTERNAL_OK=1
fi

echo ""
echo "--- Public URL (from this VPS) ---"
RESOLVE_ARGS=()
if [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]] && ! clutch_site_host_is_ip "${SITE_HOST}"; then
  RESOLVE_ARGS=( --resolve "${SITE_HOST}:${SITE_PORT}:${CLUTCH_SITE_RESOLVE_IP}" )
fi

if probe_url "public ${SITE}/" "${SITE}/" "${RESOLVE_ARGS[@]}"; then
  PUBLIC_OK=1
elif [[ "${SITE_PORT}" == "80" ]] && clutch_probe_nextjs_base_url "${SITE_HOST}" 3000 >/dev/null; then
  site_3000="$(clutch_probe_nextjs_base_url "${SITE_HOST}" 3000)"
  echo "  port 80 unreachable but Next.js OK at ${site_3000}"
  echo "  Fix: CLUTCH_SITE_URL=${site_3000}  (run: bash scripts/fix-ranked-site-url.sh)"
  if probe_url "public ${site_3000}/" "${site_3000}/"; then
    PUBLIC_OK=1
  fi
elif [[ ${#RESOLVE_ARGS[@]} -gt 0 ]]; then
  echo "  (forced IPv4 via CLUTCH_SITE_RESOLVE_IP — still failed on :${SITE_PORT})"
fi

if [[ "${PUBLIC_OK}" -eq 0 && "${INTERNAL_OK}" -eq 1 ]]; then
  echo ""
  echo "OK for api-csgo: internal URL works (public hairpin blocked — normal on same VPS)."
  echo "Set CLUTCH_SITE_INTERNAL_URL and keep CLUTCH_SITE_URL public for scoreboard/branding."
  PUBLIC_OK=1
fi

if [[ "${PUBLIC_OK}" -eq 0 && "${INTERNAL_OK}" -eq 0 ]]; then
  echo ""
  echo "FAIL: cannot reach site from this VPS."
  echo ""
  echo "Checklist:"
  echo "  1) Site Next.js running?  pm2 list  (expect 'site' or similar)"
  echo "  2) ss -tlnp | grep -E ':80|:3000'"
  echo "  3) curl -4 -s http://127.0.0.1:3000/api/health"
  echo "  4) If site is on another host (Hostinger panel), CLUTCH_SITE_URL must be that domain"
  echo "  5) Until site is live: bash scripts/push-stickers-dev-to-vps.sh (dev PC)"
  echo ""
  echo "Test without sync: sm_cvar clutch_platform_gate_enabled 0  (server console)"
  exit 1
fi

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo ""
  echo "--- steam-allowlist API ---"
  SYNC_BASE="${INTERNAL:-${SITE}}"
  SYNC_BASE="${SYNC_BASE%/}"
  API_CURL=( -4 -fsSL --max-time 10 -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" )
  if [[ "${SYNC_BASE}" == "${SITE}" && ${#RESOLVE_ARGS[@]} -gt 0 ]]; then
    API_CURL+=( "${RESOLVE_ARGS[@]}" )
  fi
  curl "${API_CURL[@]}" "${SYNC_BASE}/api/csgo/steam-allowlist" | head -c 400
  echo ""
fi

echo ""
echo "Site reachability OK."
