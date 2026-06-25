#!/usr/bin/env bash
# Ensures CLUTCH_SITE_URL / SITE_ORIGIN exist in api-csgo .env (required for sync-from-site).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
DEFAULT_SITE_URL="${CLUTCH_SITE_URL:-https://clutchclube.com.br}"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${REPO_ROOT}/.env.example" ]]; then
    cp "${REPO_ROOT}/.env.example" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from .env.example — review CSGO_SKINS_SYNC_KEY before sync."
  else
    echo "ERROR: ${ENV_FILE} not found" >&2
    exit 1
  fi
fi

missing=0
if ! grep -qE '^CLUTCH_SITE_URL=' "${ENV_FILE}"; then
  echo "CLUTCH_SITE_URL=${DEFAULT_SITE_URL}" >> "${ENV_FILE}"
  echo "Added CLUTCH_SITE_URL=${DEFAULT_SITE_URL}"
  missing=1
fi

if ! grep -qE '^SITE_ORIGIN=' "${ENV_FILE}"; then
  echo "SITE_ORIGIN=${DEFAULT_SITE_URL}" >> "${ENV_FILE}"
  echo "Added SITE_ORIGIN=${DEFAULT_SITE_URL}"
  missing=1
fi

if [[ "${missing}" -eq 0 ]]; then
  echo "OK: CLUTCH_SITE_URL and SITE_ORIGIN already set in .env"
else
  echo "Run: npm run pm2:restart"
fi
