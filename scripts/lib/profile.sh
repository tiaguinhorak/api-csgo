#!/usr/bin/env bash
# Clutch VPS profile — loaded by deploy/install scripts.
# Only SERVER_PROFILE + labels/game vars should differ per machine.

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env-file.sh"

clutch_profile_init() {
  local repo_root="${1:?repo root required}"
  CLUTCH_REPO_ROOT="${repo_root}"

  if [[ -f "${CLUTCH_REPO_ROOT}/.env" ]]; then
    env_repair_unquoted_values "${CLUTCH_REPO_ROOT}/.env"
    set -a
    # shellcheck disable=SC1091
    source "${CLUTCH_REPO_ROOT}/.env"
    set +a
  fi

  CLUTCH_SERVER_PROFILE="${SERVER_PROFILE:-ranked}"
  CLUTCH_SERVER_MODE_LABEL="${SERVER_MODE_LABEL:-}"
  CLUTCH_SERVER_NAME="${SERVER_NAME:-}"

  case "${CLUTCH_SERVER_PROFILE}" in
    ranked)
      CLUTCH_IS_RANKED=1
      CLUTCH_SERVER_POOL="${CSGO_SERVER_POOL:-ranked}"
      CLUTCH_DEFER_LIVE="${CLUTCH_DEFER_LIVE:-1}"
      ;;
    warmup|public|deathmatch|dm|surf|retake|kz|casual|arena|multimod|rifle|pistol|headshot)
      CLUTCH_IS_RANKED=0
      CLUTCH_SERVER_POOL="${CSGO_SERVER_POOL:-warmup}"
      CLUTCH_DEFER_LIVE="${CLUTCH_DEFER_LIVE:-0}"
      export WARMUP_VPS=1
      ;;
    *)
      echo "WARN: unknown SERVER_PROFILE=${CLUTCH_SERVER_PROFILE} — treating as public" >&2
      CLUTCH_IS_RANKED=0
      CLUTCH_SERVER_POOL="${CSGO_SERVER_POOL:-warmup}"
      CLUTCH_DEFER_LIVE=0
      export WARMUP_VPS=1
      ;;
  esac

  if [[ -z "${CLUTCH_SERVER_MODE_LABEL}" ]]; then
    case "${CLUTCH_SERVER_PROFILE}" in
      ranked) CLUTCH_SERVER_MODE_LABEL="Competitivo" ;;
      warmup) CLUTCH_SERVER_MODE_LABEL="Warmup" ;;
      deathmatch|dm) CLUTCH_SERVER_MODE_LABEL="Deathmatch" ;;
      surf) CLUTCH_SERVER_MODE_LABEL="Surf" ;;
      retake) CLUTCH_SERVER_MODE_LABEL="Retake" ;;
      kz) CLUTCH_SERVER_MODE_LABEL="KZ" ;;
      casual) CLUTCH_SERVER_MODE_LABEL="Casual" ;;
      *) CLUTCH_SERVER_MODE_LABEL="Público" ;;
    esac
  fi

  if [[ -z "${CLUTCH_SERVER_NAME}" ]]; then
    CLUTCH_SERVER_NAME="Clutch ${CLUTCH_SERVER_PROFILE} #1"
  fi

  export CLUTCH_SERVER_PROFILE CLUTCH_SERVER_POOL CLUTCH_DEFER_LIVE CLUTCH_IS_RANKED
  export CLUTCH_SERVER_MODE_LABEL CLUTCH_SERVER_NAME
}

clutch_profile_banner() {
  echo "Profile: ${CLUTCH_SERVER_PROFILE} | pool=${CLUTCH_SERVER_POOL} | mode=${CLUTCH_SERVER_MODE_LABEL}"
  echo "Screen: ${CLUTCH_CS_SCREEN:-?} | PORT: ${PORT:-3001}"
}
