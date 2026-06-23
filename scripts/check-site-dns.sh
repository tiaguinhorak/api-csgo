#!/usr/bin/env bash
# Verifica DNS da VPS para clutchclube.com.br (allowlist + sync do site).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

SITE="${CLUTCH_SITE_URL:-https://clutchclube.com.br}"
HOST="$(echo "${SITE}" | sed -E 's#^https?://([^/]+).*$#\1#')"

echo "=== DNS / site reachability ==="
echo "CLUTCH_SITE_URL=${SITE}"
echo "host=${HOST}"
echo ""

if command -v getent >/dev/null 2>&1; then
  echo "--- getent hosts ${HOST} ---"
  getent hosts "${HOST}" || echo "FAIL: getent cannot resolve ${HOST}"
  echo ""
fi

if command -v host >/dev/null 2>&1; then
  echo "--- host ${HOST} ---"
  host "${HOST}" || true
  echo ""
fi

echo "--- curl site (5s timeout) ---"
if curl -fsSL --max-time 5 -o /dev/null -w "HTTP %{http_code}\n" "${SITE}/"; then
  echo "OK: site responds"
else
  echo "FAIL: cannot reach ${SITE}"
  echo ""
  echo "Fix DNS on VPS (as root):"
  echo "  sudo sh -c 'printf nameserver 8.8.8.8\\nnameserver 1.1.1.1\\n > /etc/resolv.conf'"
  echo "  getent hosts ${HOST}"
  echo ""
  echo "Until DNS works, platform gate allowlist sync will fail."
  echo "Workaround for loadout sync: set CLUTCH_SITE_RESOLVE_IP=<Hostinger IP> in .env"
  echo "  then: ./scripts/sync-loadouts-from-site-curl.sh"
  echo "Temporary: sm_cvar clutch_platform_gate_enabled 0  (server console)"
  exit 1
fi

if [[ -n "${CSGO_SKINS_SYNC_KEY:-}" ]]; then
  echo ""
  echo "--- steam-allowlist API ---"
  curl -fsSL --max-time 10 -H "x-skins-sync-key: ${CSGO_SKINS_SYNC_KEY}" \
    "${SITE%/}/api/csgo/steam-allowlist" | head -c 400
  echo ""
fi
