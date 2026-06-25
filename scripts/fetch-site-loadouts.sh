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

SITE_URL="${CLUTCH_SITE_URL:-${SITE_ORIGIN:-}}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
OUT_FILE="${1:-/tmp/clutch-site-loadouts.json}"

if [[ -z "${SITE_URL}" ]]; then
  echo "ERROR: set CLUTCH_SITE_URL or SITE_ORIGIN in .env" >&2
  exit 1
fi
if [[ -z "${SYNC_KEY}" ]]; then
  echo "ERROR: CSGO_SKINS_SYNC_KEY not set" >&2
  exit 1
fi

SITE_URL="${SITE_URL%/}"
parse_clutch_site_url "${SITE_URL}"
URL="${SITE_URL}/api/csgo/skins/equipped-loadouts"

CURL_OPTS=( -sS --connect-timeout 15 -m 60 --http1.1
  -H "x-skins-sync-key: ${SYNC_KEY}"
  -H "Accept: application/json"
  -o "${OUT_FILE}"
  -w '%{http_code}'
)

if should_use_site_resolve; then
  CURL_OPTS+=( --resolve "${SITE_HOST}:${SITE_PORT}:${CLUTCH_SITE_RESOLVE_IP}" )
  echo "Using --resolve ${SITE_HOST}:${SITE_PORT}:${CLUTCH_SITE_RESOLVE_IP}"
elif [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]] && clutch_site_host_is_ip "${SITE_HOST}"; then
  echo "NOTE: CLUTCH_SITE_RESOLVE_IP ignored for direct IP URL (${SITE_HOST})"
  echo "      Remove CLUTCH_SITE_RESOLVE_IP from .env when using http://192.168.x.x:3000"
fi

HTTP_CODE="$(curl "${CURL_OPTS[@]}" "${URL}" 2>/tmp/clutch-site-loadouts-curl.err || echo "000")"
# curl prints the -w code on its own line; keep only the last token (handles "000\n000").
HTTP_CODE="$(printf '%s' "${HTTP_CODE}" | tr -d '[:space:]' | tail -c 3)"
echo "HTTP ${HTTP_CODE} → ${OUT_FILE}"

# Accept a valid payload even when curl reports a transfer-level failure (e.g. the
# server resets the connection right after sending the body → http_code 000).
body_is_valid_loadout() {
  [[ -s "${OUT_FILE}" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e '.ok == true and (.loadouts | type == "array")' "${OUT_FILE}" >/dev/null 2>&1
  else
    grep -q '"ok":[[:space:]]*true' "${OUT_FILE}"
  fi
}

if [[ "${HTTP_CODE}" != "200" ]]; then
  if body_is_valid_loadout; then
    echo "WARN: curl reported HTTP ${HTTP_CODE} but payload is valid — using it." >&2
    echo "curl note: $(cat /tmp/clutch-site-loadouts-curl.err 2>/dev/null)" >&2
    exit 0
  fi
fi

if [[ "${HTTP_CODE}" == "000" ]]; then
  echo "curl error: $(cat /tmp/clutch-site-loadouts-curl.err 2>/dev/null)" >&2
  if clutch_site_host_is_ip "${SITE_HOST}"; then
    echo "" >&2
    echo "Local dev: start site on PC (npm run dev) and allow Windows firewall port ${SITE_PORT}." >&2
    echo "Test from VPS: curl -s -o /dev/null -w '%{http_code}' ${SITE_URL}/" >&2
  fi
  exit 1
fi
if [[ "${HTTP_CODE}" != "200" ]]; then
  head -c 500 "${OUT_FILE}" 2>/dev/null || true
  echo "" >&2
  echo "ERROR: site API failed — check CSGO_SKINS_SYNC_KEY matches site .env" >&2
  if [[ -z "${CLUTCH_SITE_RESOLVE_IP:-}" ]] && ! clutch_site_host_is_ip "${SITE_HOST}"; then
    echo "If DNS fails on VPS, set CLUTCH_SITE_RESOLVE_IP=<Hostinger IP> in .env" >&2
  fi
  exit 1
fi
