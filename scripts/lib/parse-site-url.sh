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
  local resolve_ip="${CLUTCH_SITE_RESOLVE_IP:-${RESOLVED_SITE_IP:-}}"
  [[ -n "${resolve_ip}" ]] \
    && [[ "${SITE_SCHEME:-}" == https ]] \
    && ! clutch_site_host_is_ip "${SITE_HOST:-}"
}

# When the VPS resolver is broken, query Google/Cloudflare DNS directly.
clutch_resolve_site_ip() {
  local host="${1:-}"
  RESOLVED_SITE_IP=""

  if [[ -z "${host}" ]]; then
    return 1
  fi

  if clutch_site_host_is_ip "${host}"; then
    RESOLVED_SITE_IP="${host}"
    return 0
  fi

  if [[ -n "${CLUTCH_SITE_RESOLVE_IP:-}" ]]; then
    RESOLVED_SITE_IP="${CLUTCH_SITE_RESOLVE_IP}"
    return 0
  fi

  local ip=""
  if command -v dig >/dev/null 2>&1; then
    for dns in 8.8.8.8 1.1.1.1 9.9.9.9; do
      ip="$(dig +time=3 +tries=1 +short "@${dns}" "${host}" A 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1)"
      if [[ -n "${ip}" ]]; then
        break
      fi
    done
  fi

  if [[ -z "${ip}" ]] && command -v nslookup >/dev/null 2>&1; then
    ip="$(nslookup "${host}" 8.8.8.8 2>/dev/null | awk '/^Address: / { print $2; exit }' | grep -E '^[0-9]+(\.[0-9]+){3}$' || true)"
  fi

  if [[ -n "${ip}" ]]; then
    RESOLVED_SITE_IP="${ip}"
    echo "Auto-resolved ${host} → ${ip} via public DNS (set CLUTCH_SITE_RESOLVE_IP=${ip} in .env to skip lookup)"
    return 0
  fi

  return 1
}

clutch_effective_resolve_ip() {
  echo "${CLUTCH_SITE_RESOLVE_IP:-${RESOLVED_SITE_IP:-}}"
}
