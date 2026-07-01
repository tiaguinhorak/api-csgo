#!/usr/bin/env bash
# Compare .env on disk vs what api-csgo /health reports (PM2 env drift).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
source_clutch_env "${REPO_ROOT}/.env"

PORT="${PORT:-3001}"
API="http://127.0.0.1:${PORT}"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"

echo "=== Match pipeline env verify ==="
echo ""
echo "--- .env on disk ---"
grep -E '^(CLUTCH_SITE_URL|CLUTCH_SITE_INTERNAL_URL|SITE_ORIGIN|PORT|CSGO_SKINS_SYNC_KEY)=' "${REPO_ROOT}/.env" 2>/dev/null || echo "(missing .env keys)"
echo ""

echo "--- node dotenv (same as dist/index.js) ---"
node -e "
require('dotenv').config({ path: '.env' });
console.log('CLUTCH_SITE_URL=', process.env.CLUTCH_SITE_URL || '(unset)');
console.log('CLUTCH_SITE_INTERNAL_URL=', process.env.CLUTCH_SITE_INTERNAL_URL || '(unset)');
console.log('PORT=', process.env.PORT || '(unset)');
"

echo ""
echo "--- api-csgo /health (wait up to 8s) ---"
health=""
for _ in 1 2 3 4; do
  health="$(curl -4 -sf -m 2 "${API}/health" 2>/dev/null || true)"
  if [[ -n "${health}" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "${health}" ]]; then
  echo "FAIL: no JSON from ${API}/health (wrong PORT? api-csgo still starting?)"
  echo "  ss -tlnp | grep -E ':3001|:3000'"
  echo "  pm2 logs api-csgo --lines 20 --nostream"
  exit 1
fi

echo "${health}" | node -e "
const chunks = [];
process.stdin.on('data', (d) => chunks.push(d));
process.stdin.on('end', () => {
  try {
    const j = JSON.parse(Buffer.concat(chunks).toString());
    const mp = j.matchPipeline || {};
    console.log('siteUrl:        ', mp.siteUrl ?? '(missing in health — rebuild api-csgo)');
    console.log('siteRequestUrl: ', mp.siteRequestUrl ?? mp.siteUrl ?? '(missing)');
    console.log('syncKeyConfigured:', mp.syncKeyConfigured);
  } catch (e) {
    console.log('(invalid JSON)', Buffer.concat(chunks).toString().slice(0, 200));
  }
});
"

echo ""
echo "--- site POST probe ---"
if [[ -z "${SYNC_KEY}" ]]; then
  echo "WARN: CSGO_SKINS_SYNC_KEY unset"
else
  base="${CLUTCH_SITE_INTERNAL_URL:-${CLUTCH_SITE_URL:-}}"
  base="${base%/}"
  code="$(curl -4 -s -o /tmp/clutch-mp-probe.txt -w "%{http_code}" \
    -X POST "${base}/api/csgo/match-result" \
    -H "Content-Type: application/json" \
    -H "x-skins-sync-key: ${SYNC_KEY}" \
    -d '{"csgoMatchId":"env-probe","roomId":"probe","scoreTeamA":0,"scoreTeamB":0,"durationSec":0,"players":[]}' \
    2>/dev/null || echo "000")"
  body="$(head -c 120 /tmp/clutch-mp-probe.txt 2>/dev/null || true)"
  echo "POST ${base}/api/csgo/match-result → HTTP ${code} ${body}"
  if [[ "${code}" == "404" && "${body}" == *"<!DOCTYPE"* ]]; then
    echo ""
    echo "FAIL: still hitting HTML (wrong URL — likely port 80 without :3000 in PM2 env)"
    echo "Fix: pm2 delete api-csgo && pm2 start ecosystem.config.js --update-env"
  fi
fi

echo ""
echo "--- recent boot log ---"
pm2 logs api-csgo --lines 40 --nostream 2>&1 | grep -E '\[boot\]|site forward|CS:GO API running' | tail -8 || true
