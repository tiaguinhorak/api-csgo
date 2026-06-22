#!/usr/bin/env bash
# Mata processos node da api-csgo que NÃO estão no pm2 (ex.: PID órfão em :3000).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

API_PORT="${PORT:-3000}"
MY_UID="$(id -u)"
KILLED=0

kill_pid() {
  local pid="$1"
  if [[ -z "${pid}" ]] || [[ "${pid}" == "$$" ]]; then
    return 0
  fi
  if ! kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  echo "[kill-stale] SIGKILL pid ${pid} ($(ps -p "${pid}" -o args= 2>/dev/null || echo '?'))"
  kill -9 "${pid}" 2>/dev/null || true
  KILLED=$((KILLED + 1))
}

kill_pgrep_patterns() {
  local pattern="$1"
  local pid
  while IFS= read -r pid; do
    kill_pid "${pid}"
  done < <(pgrep -u "${MY_UID}" -f "${pattern}" 2>/dev/null || true)
}

echo "[kill-stale] Stopping pm2 apps (if any)..."
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete api-csgo 2>/dev/null || true
fi

echo "[kill-stale] Killing api-csgo node processes..."
for round in 1 2 3; do
  kill_pgrep_patterns "${REPO_ROOT}/dist/index.js"
  kill_pgrep_patterns 'api-csgo/dist/index.js'
  kill_pgrep_patterns 'api_csgo/dist/index.js'
  sleep 1
done

echo "[kill-stale] Freeing TCP :${API_PORT}..."
for attempt in 1 2 3 4 5 6; do
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${API_PORT}/tcp" 2>/dev/null || true
  fi

  if command -v ss >/dev/null 2>&1; then
    while IFS= read -r pid; do
      if [[ "${pid}" =~ ^[0-9]+$ ]]; then
        kill_pid "${pid}"
      fi
    done < <(ss -Htnlp 2>/dev/null | grep -E ":${API_PORT}\\s" | grep -oE 'pid=[0-9]+' | sed 's/pid=//' || true)
  fi

  if command -v lsof >/dev/null 2>&1; then
    while IFS= read -r pid; do
      kill_pid "${pid}"
    done < <(lsof -ti :"${API_PORT}" 2>/dev/null || true)
  fi

  sleep 1

  if ! ss -tln 2>/dev/null | grep -q ":${API_PORT} "; then
    break
  fi
done

if ss -tln 2>/dev/null | grep -q ":${API_PORT} "; then
  echo "[kill-stale] ERROR: port ${API_PORT} still in use." >&2
  pgrep -u "${MY_UID}" -af 'node|api-csgo' 2>/dev/null || true
  echo "Manual: kill -9 \$(pgrep -u ${MY_UID} -f '${REPO_ROOT}/dist/index.js')" >&2
  exit 1
fi

echo "[kill-stale] OK — port ${API_PORT} free (killed ${KILLED} process(es))"
