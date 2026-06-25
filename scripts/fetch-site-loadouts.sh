#!/usr/bin/env bash
# Fetch equipped-loadouts JSON from site (optional CLUTCH_SITE_RESOLVE_IP when VPS DNS fails).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=lib/parse-site-url.sh
source "${REPO_ROOT}/scripts/lib/parse-site-url.sh"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SITE_URL="${CLUTCH_SITE_URL:-${SITE_ORIGIN:-https://clutchclube.com.br}}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
OUT_FILE="${1:-/tmp/clutch-site-loadouts.json}"
RESOLVED_SITE_IP=""

if [[ -z "${SYNC_KEY}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set in .env (must match site/.env)" >&2
  exit 1
fi

if [[ "${CLUTCH_SITE_URL:-}" == "" && "${SITE_ORIGIN:-}" == "" ]]; then
  echo "NOTE: using default CLUTCH_SITE_URL=${SITE_URL}"
fi

fetch_loadouts_from_url() {
  local base_url="$1"
  local label="$2"

  base_url="${base_url%/}"
  parse_clutch_site_url "${base_url}"
  local url="${base_url}/api/csgo/skins/equipped-loadouts"

  if ! clutch_site_host_is_ip "${SITE_HOST}"; then
    clutch_resolve_site_ip "${SITE_HOST}" || true
  fi

  local resolve_ip
  resolve_ip="$(clutch_effective_resolve_ip)"

  local curl_opts=( -sS --connect-timeout 15 -m 60 --http1.1
    -H "x-skins-sync-key: ${SYNC_KEY}"
    -H "Accept: application/json"
    -o "${OUT_FILE}"
    -w '%{http_code}'
  )

  if [[ -n "${resolve_ip}" ]] && [[ "${SITE_SCHEME}" == https ]] && ! clutch_site_host_is_ip "${SITE_HOST}"; then
    curl_opts+=( --resolve "${SITE_HOST}:${SITE_PORT}:${resolve_ip}" )
    echo "Using --resolve ${SITE_HOST}:${SITE_PORT}:${resolve_ip} (${label})"
  fi

  local http_code
  http_code="$(curl "${curl_opts[@]}" "${url}" 2>/tmp/clutch-site-loadouts-curl.err || echo "000")"
  http_code="$(printf '%s' "${http_code}" | tr -d '[:space:]' | tail -c 3)"
  echo "HTTP ${http_code} → ${OUT_FILE} (${label})"

  body_is_valid_loadout() {
    [[ -s "${OUT_FILE}" ]] || return 1
    if command -v jq >/dev/null 2>&1; then
      jq -e '.ok == true and (.loadouts | type == "array")' "${OUT_FILE}" >/dev/null 2>&1
    else
      grep -q '"ok":[[:space:]]*true' "${OUT_FILE}"
    fi
  }

  if [[ "${http_code}" != "200" ]]; then
    if body_is_valid_loadout; then
      echo "WARN: curl reported HTTP ${http_code} but payload is valid — using it." >&2
      echo "curl note: $(cat /tmp/clutch-site-loadouts-curl.err 2>/dev/null)" >&2
      return 0
    fi
  fi

  if [[ "${http_code}" == "000" ]]; then
    echo "curl error: $(cat /tmp/clutch-site-loadouts-curl.err 2>/dev/null)" >&2
    return 1
  fi

  if [[ "${http_code}" != "200" ]]; then
    head -c 500 "${OUT_FILE}" 2>/dev/null || true
    echo "" >&2
    echo "ERROR: site API failed (HTTP ${http_code}) — check CSGO_SKINS_SYNC_KEY matches site .env" >&2
    return 1
  fi

  return 0
}

if ! fetch_loadouts_from_url "${SITE_URL}" "primary ${SITE_URL}"; then
  FALLBACK_URL="${CLUTCH_SITE_FALLBACK_URL:-${CLUTCH_SITE_LAN_URL:-}}"
  if [[ -n "${FALLBACK_URL}" ]]; then
    echo ""
    echo ">>> Retrying with CLUTCH_SITE_FALLBACK_URL=${FALLBACK_URL}"
    if fetch_loadouts_from_url "${FALLBACK_URL}" "fallback ${FALLBACK_URL}"; then
      exit 0
    fi
  fi

  echo "" >&2
  echo "DNS/sync fixes:" >&2
  echo "  1) Install dig: sudo apt install dnsutils" >&2
  echo "  2) Add to .env: CLUTCH_SITE_RESOLVE_IP=<site A record IP>" >&2
  echo "  3) Or LAN dev site: CLUTCH_SITE_FALLBACK_URL=http://192.168.100.6:3000" >&2
  echo "  4) Or point primary: CLUTCH_SITE_URL=http://192.168.100.6:3000" >&2
  exit 1
fi
