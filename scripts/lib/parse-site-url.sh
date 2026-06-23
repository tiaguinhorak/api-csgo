#!/usr/bin/env bash
# Parse CLUTCH_SITE_URL into SITE_HOST, SITE_PORT, SITE_SCHEME (source this file).
set -euo pipefail

parse_clutch_site_url() {
  local raw="${1:-}"
  raw="${raw%/}"
  SITE_SCHEME=http
  SITE_HOST=""
  SITE_PORT=""

  if [[ "${raw}" =~ ^https://([^/]+) ]]; then
    SITE_SCHEME=https
    SITE_HOST="${BASH_REMATCH[1]}"
  elif [[ "${raw}" =~ ^http://([^/]+) ]]; then
    SITE_SCHEME=http
    SITE_HOST="${BASH_REMATCH[1]}"
  else
    SITE_HOST="${raw}"
  fi

  if [[ "${SITE_HOST}" =~ ^([^:]+):([0-9]+)$ ]]; then
    SITE_HOST="${BASH_REMATCH[1]}"
    SITE_PORT="${BASH_REMATCH[2]}"
  fi

  if [[ -z "${SITE_PORT}" ]]; then
    if [[ "${SITE_SCHEME}" == https ]]; then
      SITE_PORT=443
    else
      SITE_PORT=80
    fi
  fi
}

clutch_site_host_is_ip() {
  local h="${1:-}"
  [[ "${h}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || [[ "${h}" =~ ^\[.*\]$ ]]
}

should_use_site_resolve() {
  local resolve_ip="${CLUTCH_SITE_RESOLVE_IP:-}"
  [[ -n "${resolve_ip}" ]] \
    && [[ "${SITE_SCHEME:-}" == https ]] \
    && ! clutch_site_host_is_ip "${SITE_HOST:-}"
}
