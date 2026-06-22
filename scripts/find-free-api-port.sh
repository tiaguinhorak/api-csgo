#!/usr/bin/env bash
# Pick a TCP port the csgo user can bind (skips ports already LISTEN on the host).
set -euo pipefail

START_PORT="${1:-3001}"
END_PORT="${2:-3099}"

port_in_use() {
  local port="$1"
  command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":${port} "
}

for ((port = START_PORT; port <= END_PORT; port++)); do
  if ! port_in_use "${port}"; then
    echo "${port}"
    exit 0
  fi
done

echo "ERROR: no free port in ${START_PORT}-${END_PORT}" >&2
exit 1
