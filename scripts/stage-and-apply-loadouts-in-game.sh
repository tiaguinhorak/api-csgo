#!/usr/bin/env bash
# Stage web loadouts + apply skins/gloves in srcds (same as ranked player-sync RCON tail).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

STEAM_ID="${1:-}"

resolve_screen_session() {
  local preferred="${CLUTCH_CS_SCREEN:-csgo-clutch-#1}"
  local line full

  if screen -ls 2>/dev/null | grep -qF ".${preferred}"; then
    full="$(screen -ls 2>/dev/null | grep -F ".${preferred}" | head -1 | awk '{print $1}')"
    if [[ -n "${full}" ]]; then
      echo "${full}"
      return 0
    fi
  fi

  while IFS= read -r line; do
    if [[ "${line}" == *"(Detached)"* ]] && [[ "${line}" == *"csgo-"* ]]; then
      full="$(echo "${line}" | awk '{print $1}')"
      if [[ -n "${full}" ]]; then
        echo "${full}"
        return 0
      fi
    fi
  done < <(screen -ls 2>/dev/null || true)

  return 1
}

send_screen_cmd() {
  local session="$1"
  local cmd="$2"
  local wait="${3:-0.5}"
  echo ">>> screen: ${cmd}"
  screen -S "${session}" -p 0 -X stuff "${cmd}^M" || \
    screen -S "${session}" -X stuff "${cmd}^M"
  sleep "${wait}"
}

send_rcon_cmd() {
  local cmd="$1"
  local host="${CSGO_SERVER_HOST:-127.0.0.1}"
  local port="${CSGO_RCON_PORT:-27015}"
  local pass="${CSGO_RCON_PASSWORD:-}"

  if [[ -z "${pass}" ]]; then
    return 1
  fi

  if [[ "${CSGO_RCON_LOOPBACK:-}" == "1" ]]; then
    host="127.0.0.1"
  fi

  if command -v rcon-cli >/dev/null 2>&1; then
    echo ">>> rcon: ${cmd}"
    rcon-cli -H "${host}" -p "${port}" -P "${pass}" "${cmd}" && return 0
  fi

  return 1
}

FULL_SCREEN="$(resolve_screen_session || true)"

if send_rcon_cmd "sm plugins reload weapons"; then
  :
elif [[ -n "${FULL_SCREEN}" ]]; then
  send_screen_cmd "${FULL_SCREEN}" "sm plugins reload weapons" 1.2
fi

if send_rcon_cmd "sm_clutch_gloves_refresh"; then
  :
elif [[ -n "${FULL_SCREEN}" ]]; then
  send_screen_cmd "${FULL_SCREEN}" "sm_clutch_gloves_refresh" 0.8
fi

if send_rcon_cmd "sm_clutch_gloves_apply"; then
  :
elif [[ -n "${FULL_SCREEN}" ]]; then
  send_screen_cmd "${FULL_SCREEN}" "sm_clutch_gloves_apply" 0.6
fi

if send_rcon_cmd "sm_clutch_applyskins"; then
  echo "In-game apply OK (RCON)."
  exit 0
fi

if [[ -n "${FULL_SCREEN}" ]]; then
  send_screen_cmd "${FULL_SCREEN}" "sm_clutch_applyskins" 2.5
  echo "In-game apply OK (screen ${FULL_SCREEN})."
  exit 0
fi

echo "WARN: applyskins failed — CS offline?" >&2
exit 1
