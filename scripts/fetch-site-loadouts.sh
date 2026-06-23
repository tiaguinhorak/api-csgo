#!/usr/bin/env bash
# Fetch equipped-loadouts JSON from site (optional CLUTCH_SITE_RESOLVE_IP when VPS DNS fails).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

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
HOST="$(echo "${SITE_URL}" | sed -E 's#^https?://([^/]+).*$#\1#')"
URL="${SITE_URL}/api/csgo/skins/equipped-loadouts"

CURL_OPTS=( -sS --connect-timeout 15 -m 60
  -H "x-skins-sync-key: ${SYNC_KEY}"
  -H "Accept: application/json"
  -o "${OUT_FILE}"
  -w '%{http_code}'
)

if [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]]; then
  CURL_OPTS+=( --resolve "${HOST}:443:${CLUTCH_SITE_RESOLVE_IP}" )
  echo "Using --resolve ${HOST}:443:${CLUTCH_SITE_RESOLVE_IP}"
fi

HTTP_CODE="$(curl "${CURL_OPTS[@]}" "${URL}" 2>/tmp/clutch-site-loadouts-curl.err || echo "000")"
echo "HTTP ${HTTP_CODE} → ${OUT_FILE}"

if [[ "${HTTP_CODE}" == "000" ]]; then
  echo "curl error: $(cat /tmp/clutch-site-loadouts-curl.err 2>/dev/null)" >&2
  exit 1
fi
if [[ "${HTTP_CODE}" != "200" ]]; then
  head -c 500 "${OUT_FILE}" >&2
  echo "" >&2
  echo "ERROR: site API failed — check CSGO_SKINS_SYNC_KEY matches site .env" >&2
  if [[ -z "${CLUTCH_SITE_RESOLVE_IP:-}" ]]; then
    echo "If DNS fails on VPS, set CLUTCH_SITE_RESOLVE_IP=<Hostinger IP> in .env" >&2
  fi
  exit 1
fi
