#!/usr/bin/env bash
# Compare api-csgo live matches vs clutch_match_live SQLite rows.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/env-file.sh"
source_clutch_env "${REPO_ROOT}/.env"

PORT="${PORT:-3001}"
API="http://127.0.0.1:${PORT}"

DB="${CLUTCH_MATCH_DB_PATH:-}"
if [[ -z "${DB}" ]]; then
  DB="$(node -e "const { getMatchLiveDbPath } = require('./dist/services/weapons-db-path'); console.log(getMatchLiveDbPath());" 2>/dev/null || true)"
fi
if [[ -z "${DB}" ]]; then
  DB="/home/csgo/server/csgo/addons/sourcemod/data/sqlite/storage-local.sq3"
fi

echo "=== Clutch match tracker diagnose ==="
echo "API:            ${API}"
echo "SQLite:         ${DB}"
echo "CLUTCH_SITE_INTERNAL_URL: ${CLUTCH_SITE_INTERNAL_URL:-(not set)}"
echo ""

echo "--- Live matches (api-csgo) ---"
API_KEY="${API_KEY:-${CSGO_API_KEY:-${CSGO_SKINS_SYNC_KEY:-}}}"
AUTH_ARGS=()
if [[ -n "${API_KEY}" ]]; then
  AUTH_ARGS=(-H "x-api-key: ${API_KEY}")
else
  echo "WARN: API_KEY not set — /api/matches requires auth"
fi

LIVE_JSON="$(curl -sf "${AUTH_ARGS[@]}" "${API}/api/matches?status=live" 2>/dev/null || echo '[]')"
echo "${LIVE_JSON}" | node -e "
const chunks = [];
process.stdin.on('data', (d) => chunks.push(d));
process.stdin.on('end', () => {
  let rows = [];
  try { rows = JSON.parse(Buffer.concat(chunks).toString() || '[]'); } catch { rows = []; }
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log('(none — no status=live in api-csgo)');
    return;
  }
  for (const m of rows) {
    console.log('matchId=' + m.id + ' roomId=' + m.roomId + ' map=' + (m.selectedMap ?? '?'));
  }
});
"

echo ""
echo "--- All matches in store (any status) ---"
ALL_JSON="$(curl -sf "${AUTH_ARGS[@]}" "${API}/api/matches" 2>/dev/null || echo '[]')"
echo "${ALL_JSON}" | node -e "
const chunks = [];
process.stdin.on('data', (d) => chunks.push(d));
process.stdin.on('end', () => {
  let rows = [];
  try { rows = JSON.parse(Buffer.concat(chunks).toString() || '[]'); } catch { rows = []; }
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log('(none — api-csgo has no match records)');
    return;
  }
  for (const m of rows.slice(-8)) {
    console.log('status=' + m.status + ' matchId=' + m.id + ' roomId=' + m.roomId);
  }
});
"

echo ""
echo "--- store.json (persisted state) ---"
if [[ -f "${REPO_ROOT}/data/store.json" ]]; then
  node -e "
const s = require('./data/store.json');
const ms = Array.isArray(s.matches) ? s.matches : [];
if (!ms.length) { console.log('(no matches in store.json)'); process.exit(0); }
for (const m of ms.slice(-8)) {
  console.log('status=' + m.status + ' matchId=' + m.id + ' roomId=' + m.roomId);
}
"
else
  echo "(missing data/store.json)"
fi

echo ""
echo "--- clutch_match_live (plugin DB) ---"
if [[ ! -f "${DB}" ]]; then
  echo "FAIL: DB not found: ${DB}"
  exit 1
fi

sqlite3 "${DB}" \
  "SELECT match_id, phase, score_team_a, score_team_b, round_num, updated_at FROM clutch_match_live ORDER BY updated_at DESC LIMIT 5;" \
  | while IFS='|' read -r id phase sa sb rnd upd; do
    if [[ -z "${id}" ]]; then
      echo "(empty)"
    else
      echo "match_id=${id} phase=${phase} score=${sa}:${sb} round=${rnd} updated=${upd}"
    fi
  done

echo ""
echo "--- Port check (Next.js site ≠ api-csgo) ---"
API_PORT="${PORT:-3001}"
for p in 3000 "${API_PORT}"; do
  health="$(curl -s -m 2 "http://127.0.0.1:${p}/health" 2>/dev/null || true)"
  if [[ -n "${health}" ]]; then
    if echo "${health}" | grep -q 'glovesPlayerSync\|matchPipeline'; then
      echo "  :${p} → api-csgo Express (NOT the Next.js site — /api/csgo/match-result does not exist here)"
    elif echo "${health}" | grep -q '"database"'; then
      echo "  :${p} → Next.js site (/api/health OK)"
    else
      echo "  :${p} → /health responds: ${health:0:80}"
    fi
  else
    echo "  :${p} → (no /health response)"
  fi
done
echo "  api-csgo fetch uses CLUTCH_SITE_INTERNAL_URL when set (same VPS); public URL for branding."

echo ""
echo "--- Site API probe (POST /api/csgo/match-result) ---"
SYNC_KEY="${CSGO_SKINS_SYNC_KEY:-}"
if [[ -z "${SYNC_KEY}" ]]; then
  echo "WARN: CSGO_SKINS_SYNC_KEY not set — cannot probe site"
else
  probe_site() {
    local base="$1"
    local label="$2"
    if [[ -z "${base}" ]]; then
      echo "  ${label}: (empty URL)"
      return
    fi
    base="${base%/}"
    local code body_snip
    code="$(curl -s -o /tmp/clutch-probe-body.txt -w "%{http_code}" \
      -X POST "${base}/api/csgo/match-result" \
      -H "Content-Type: application/json" \
      -H "x-skins-sync-key: ${SYNC_KEY}" \
      -d '{"csgoMatchId":"diagnose-probe","roomId":"probe","scoreTeamA":0,"scoreTeamB":0,"durationSec":0,"players":[]}' \
      2>/dev/null || echo "000")"
    body_snip="$(head -c 120 /tmp/clutch-probe-body.txt 2>/dev/null | tr '\n' ' ')"
    if [[ "${code}" == "400" && "${body_snip}" == *"Invalid payload"* ]]; then
      echo "  ${label} ${base}/api/csgo/match-result → HTTP ${code} (OK — Next.js route exists, auth OK)"
    elif [[ "${code}" == "401" ]]; then
      echo "  ${label} ${base}/api/csgo/match-result → HTTP ${code} (route exists — CSGO_SKINS_SYNC_KEY mismatch with site/.env)"
    elif [[ "${code}" == "404" && "${body_snip}" == *"<!DOCTYPE"* ]]; then
      echo "  ${label} ${base}/api/csgo/match-result → HTTP ${code} (HTML — nginx/default page, not Next.js API)"
    elif [[ "${code}" == "404" ]]; then
      echo "  ${label} ${base}/api/csgo/match-result → HTTP ${code} ${body_snip} (route missing — deploy latest site build)"
    else
      echo "  ${label} ${base}/api/csgo/match-result → HTTP ${code} ${body_snip}"
    fi
  }
  probe_site "${CLUTCH_SITE_URL:-}" "configured (public)"
  if [[ -n "${CLUTCH_SITE_INTERNAL_URL:-}" ]]; then
    probe_site "${CLUTCH_SITE_INTERNAL_URL}" "internal (api-csgo fetch)"
  fi
  for port in 3000 3002; do
    probe_site "http://127.0.0.1:${port}" "127.0.0.1:${port}"
    health="$(curl -4 -sf -m 2 "http://127.0.0.1:${port}/api/health" 2>/dev/null || true)"
    if echo "${health}" | grep -q '"database"'; then
      echo "  → Next.js detected on :${port} — set CLUTCH_SITE_INTERNAL_URL=http://127.0.0.1:${port}"
      break
    fi
  done
  echo ""
  echo "  Expected on site: HTTP 400 with {\"error\":\"Invalid payload\"...}"
  echo "  Same VPS: bash scripts/fix-ranked-site-url.sh (sets CLUTCH_SITE_INTERNAL_URL)"
  echo "  Then: pm2 restart api-csgo --update-env"
fi

echo ""
echo "--- ID overlap (store.json vs clutch_match_live) ---"
if [[ -f "${REPO_ROOT}/data/store.json" ]]; then
  DB="${DB}" node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const db = process.env.DB;
const store = require('./data/store.json');
const storeIds = new Set((store.matches || []).map((m) => m.id));
let sqliteIds = [];
try {
  const out = execSync(
    'sqlite3 ' + JSON.stringify(db) + ' \"SELECT match_id FROM clutch_match_live WHERE phase=\\'finished\\' ORDER BY updated_at DESC LIMIT 20;\"',
    { encoding: 'utf8' },
  );
  sqliteIds = out.trim().split(/\\n/).filter(Boolean);
} catch (e) {
  console.log('(could not read SQLite)');
  process.exit(0);
}
const overlap = sqliteIds.filter((id) => storeIds.has(id));
const orphan = sqliteIds.filter((id) => !storeIds.has(id));
if (overlap.length) {
  console.log('matching IDs (can replay): ' + overlap.join(', '));
} else {
  console.log('matching IDs: (none)');
}
if (orphan.length) {
  console.log('orphan SQLite rows (no store match — clutch_match_begin used wrong id): ' + orphan.slice(0, 5).join(', '));
}
"
else
  echo "(no store.json)"
fi

echo ""
echo "--- Recent api-csgo logs (match-start / tracker) ---"
pm2 logs api-csgo --lines 120 --nostream 2>&1 | grep -E 'match-start|match-live|match-result|tracker' | tail -20 || echo "(no lines)"

echo ""
echo "If api-csgo has a live match but plugin DB differs, in SERVER console (screen -r):"
echo "  clutch_match_clear"
echo "  clutch_match_begin <matchId-from-api-above> 30"
echo "  clutch_match_roster \"STEAM_A|...\" \"STEAM_B|...\""
echo "After the match: clutch_match_finish  (or play until cs_win_panel_match)"
echo ""
echo "After fixing CLUTCH_SITE_URL, replay rows that match store.json:"
echo "  bash scripts/replay-pending-match-results.sh --dry-run"
echo "  bash scripts/replay-pending-match-results.sh"
