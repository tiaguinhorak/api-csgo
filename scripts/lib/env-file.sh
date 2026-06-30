#!/usr/bin/env bash
# Helpers for safe .env read/write (values with spaces or # must be quoted).

env_quote_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

env_set_kv_if_missing() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  if ! grep -qE "^${key}=" "${env_file}"; then
    echo "${key}=$(env_quote_value "${value}")" >> "${env_file}"
    echo "Added ${key}=$(env_quote_value "${value}")"
  fi
}

# Fix legacy lines like SERVER_NAME=Clutch ranked #1 (breaks `source .env`).
env_repair_unquoted_values() {
  local env_file="$1"
  local keys=(SERVER_NAME SERVER_MODE_LABEL)
  local key line value

  [[ -f "${env_file}" ]] || return 0

  for key in "${keys[@]}"; do
    line="$(grep -E "^${key}=" "${env_file}" | tail -1 || true)"
    [[ -n "${line}" ]] || continue

    value="${line#${key}=}"
    if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
      continue
    fi
    if [[ "${value}" != *" "* && "${value}" != *"#"* ]]; then
      continue
    fi

    sed -i "/^${key}=/d" "${env_file}"
    echo "${key}=$(env_quote_value "${value}")" >> "${env_file}"
    echo "Fixed ${key} quoting in ${env_file}"
  done
}

source_clutch_env() {
  local env_file="${1:?env file required}"
  [[ -f "${env_file}" ]] || return 0
  env_repair_unquoted_values "${env_file}"
  set -a
  # shellcheck disable=SC1091
  source "${env_file}"
  set +a
}
