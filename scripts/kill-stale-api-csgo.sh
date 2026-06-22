#!/usr/bin/env bash
# Mata processos node da api-csgo que NÃO estão no pm2 (ex.: PID órfão em :3000).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

API_PORT="${PORT:-3000}"
MY_UID="$(id -u)"
KILLED=0

should_skip_pid() {
  local pid="$1"
  local args
  args="$(ps -p "${pid}" -o args= 2>/dev/null || true)"
  if [[ -z "${args}" ]]; then
    return 0
  fi
  case "${args}" in
    *kill-stale-api-csgo.sh*|*pm2-ensure-api-csgo.sh*|*deploy-vps.sh*)
      return 0
      ;;
  esac
  if [[ "${args}" == *bash* ]] && [[ "${args}" != *node* ]] && [[ "${args}" != *dist/index.js* ]]; then
    return 0
  fi
  return 1
}

kill_pid() {
  local pid="$1"
  if [[ -z "${pid}" ]] || [[ "${pid}" == "$$" ]] || [[ "${pid}" == "${PPID}" ]]; then
    return 0
  fi
  if should_skip_pid "${pid}"; then
    return 0
  fi
  if ! kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  if ! kill -9 "${pid}" 2>/dev/null; then
    echo "[kill-stale] WARN: could not kill pid ${pid} (other user?) — try: sudo bash scripts/fix-port-3000-as-root.sh" >&2
    return 1
  fi
  echo "[kill-stale] SIGKILL pid ${pid} ($(ps -p "${pid}" -o args= 2>/dev/null || echo '?'))"
  KILLED=$((KILLED + 1))
}

kill_pgrep_patterns_all_users() {
  local pattern="$1"
  local pid
  while IFS= read -r pid; do
    kill_pid "${pid}" || true
  done < <(pgrep -f "${pattern}" 2>/dev/null || true)
}

port_still_listening() {
  command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":${API_PORT} "
}

kill_pgrep_patterns() {
  local pattern="$1"
  local pid
  while IFS= read -r pid; do
    kill_pid "${pid}"
  done < <(pgrep -u "${MY_UID}" -f "${pattern}" 2>/dev/null || true)
}

is_node_pid() {
  local pid="$1"
  local comm
  comm="$(ps -p "${pid}" -o comm= 2>/dev/null || true)"
  [[ "${comm}" == node ]] || [[ "${comm}" == nodejs ]]
}

kill_node_listeners_on_port() {
  local pid

  if command -v lsof >/dev/null 2>&1; then
    while IFS= read -r pid; do
      if [[ "${pid}" =~ ^[0-9]+$ ]] && is_node_pid "${pid}"; then
        kill_pid "${pid}"
      fi
    done < <(lsof -ti :"${API_PORT}" -sTCP:LISTEN 2>/dev/null || true)
  fi

  if command -v ss >/dev/null 2>&1; then
    while IFS= read -r pid; do
      if [[ "${pid}" =~ ^[0-9]+$ ]] && is_node_pid "${pid}"; then
        kill_pid "${pid}"
      fi
    done < <(
      ss -Htnlp 2>/dev/null | grep -E ":${API_PORT}\\s" | grep -oE 'pid=[0-9]+' | sed 's/pid=//' | sort -u || true
    )
  fi
}

echo "[kill-stale] Stopping pm2 apps (if any)..."
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete api-csgo 2>/dev/null || true
fi

echo "[kill-stale] Killing node listeners on :${API_PORT}..."
kill_node_listeners_on_port

echo "[kill-stale] Killing api-csgo node processes (all users, best effort)..."
for round in 1 2 3; do
  kill_pgrep_patterns "${REPO_ROOT}/dist/index.js"
  kill_pgrep_patterns 'api-csgo/dist/index.js'
  kill_pgrep_patterns 'api_csgo/dist/index.js'
  kill_pgrep_patterns 'dist/index.js'
  kill_pgrep_patterns_all_users 'dist/index.js'
  kill_pgrep_patterns_all_users 'api-csgo/dist/index.js'
  kill_node_listeners_on_port
  sleep 1
done

echo "[kill-stale] Processes matching dist/index.js (any user):"
pgrep -af 'dist/index.js' 2>/dev/null || echo "(none visible)"

echo "[kill-stale] Freeing TCP :${API_PORT}..."
for attempt in 1 2 3 4 5 6; do
  kill_node_listeners_on_port

  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${API_PORT}/tcp" 2>/dev/null || true
  fi

  sleep 1

  if ! ss -tln 2>/dev/null | grep -q ":${API_PORT} "; then
    break
  fi
done

if port_still_listening; then
  echo "[kill-stale] FAIL: port ${API_PORT} still LISTEN." >&2
  ss -tlnp 2>/dev/null | grep -E ":${API_PORT}\\s" || ss -tln 2>/dev/null | grep -E ":${API_PORT}\\s" || true
  pgrep -af 'dist/index.js|api-csgo' 2>/dev/null || true
  if ss -tlnp 2>/dev/null | grep -E ":${API_PORT}\\s" | grep -qv 'pid='; then
    echo "[kill-stale] ss shows no pid — listener is another user's process." >&2
    echo "Run as admin: sudo bash ${REPO_ROOT}/scripts/fix-port-3000-as-root.sh" >&2
  fi
  exit 2
fi

echo "[kill-stale] OK — port ${API_PORT} free (killed ${KILLED} process(es))"
