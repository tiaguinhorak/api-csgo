#!/usr/bin/env bash
# Diagnose why rip.ext (REST in Pawn) fails to load on CS:GO srcds.
# Run on VPS: bash scripts/diagnose-ripext.sh

set -euo pipefail

CSGO_ROOT="${CSGO_ROOT:-/home/csgo/server/csgo}"
SM="${CSGO_ROOT}/addons/sourcemod"
RIP_SO="${SM}/extensions/rip.ext.so"
PTAH_SO="$(ls "${SM}/extensions/PTaH.ext"*.so 2>/dev/null | head -1 || true)"

echo "=== rip.ext diagnostic ==="
echo "CSGO_ROOT=${CSGO_ROOT}"
echo ""

if [[ ! -f "${RIP_SO}" ]]; then
  echo "ERROR: missing ${RIP_SO}"
  exit 1
fi

echo "--- rip.ext.so ---"
ls -la "${RIP_SO}"
file "${RIP_SO}" || true
size="$(wc -c < "${RIP_SO}" | tr -d ' ')"
echo "size=${size} (sm-ripext 1.3.2 expects ~5008816)"
if [[ "${size}" -lt 4000000 ]]; then
  echo "WARN: file too small — reinstall sm-ripext 1.3.2 linux zip"
fi
echo ""

echo "--- mount (noexec check) ---"
if command -v findmnt >/dev/null 2>&1; then
  findmnt -T "${RIP_SO}" || true
else
  echo "(findmnt not available)"
fi
echo ""

echo "--- ldd rip.ext.so ---"
ldd "${RIP_SO}" 2>&1 || true
echo ""

if [[ -n "${PTAH_SO}" && -f "${PTAH_SO}" ]]; then
  echo "--- ldd PTaH (working extension for comparison) ---"
  ldd "${PTAH_SO}" 2>&1 || true
  echo ""
fi

echo "--- i386 libcurl (ripext often dlopen's this at runtime) ---"
if command -v dpkg >/dev/null 2>&1; then
  dpkg -l 'libcurl4:i386' 'libcurl4t64:i386' 2>/dev/null | grep -E '^ii' || echo "libcurl i386 NOT installed"
fi
for p in /usr/lib/i386-linux-gnu/libcurl.so.4 /lib/i386-linux-gnu/libcurl.so.4; do
  if [[ -f "${p}" ]]; then
    ls -la "${p}"
  fi
done
echo ""

echo "--- extensions clutter ---"
ls -la "${SM}/extensions/" | grep -iE 'rip|scramble|curl' || true
echo ""

echo "--- srcds process ---"
pgrep -a -f srcds_linux || echo "(no srcds_linux — start server after fixing)"
echo ""

echo "--- recent SourceMod logs (rip / extension errors) ---"
log_dir="${SM}/logs"
if [[ -d "${log_dir}" ]]; then
  grep -iE 'rip\.ext|ripext|libcurl|REST in Pawn' "${log_dir}"/*.log 2>/dev/null | tail -20 || echo "(no rip lines in sm logs)"
else
  echo "(no ${log_dir})"
fi
echo ""

echo "=== Next steps ==="
echo "1. Install curl stack (Noble names):"
echo "   sudo apt install -y libcurl4t64:i386 libnghttp2-14:i386 libldap2:i386 libpsl5t64:i386 libssh-4:i386 librtmp1:i386 libbrotli1:i386 libidn2-0:i386"
echo "2. Remove Windows-only optional extension files:"
echo "   rm -f ${SM}/extensions/sourcescramble.ext.so ${SM}/extensions/sourcescramble.autoload"
echo "3. FULL restart srcds (kill process, start again — not just screen detach):"
echo "   cd ~/api-csgo && bash scripts/start-csgo-screen.sh"
echo "4. In SERVER console after boot:"
echo "   sm exts load rip.ext"
echo "   sm exts list"
echo "   sm plugins load eItems"
echo "   sm plugins load csgo_weaponstickers"
