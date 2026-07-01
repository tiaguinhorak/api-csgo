/**
 * Re-forward finished SQLite rows whose match_id exists in store.json.
 * Usage: npm run build && node dist/tools/replay-pending-results.js [--dry-run]
 */
import 'dotenv/config';
import { listFinishedMatchLiveRowsAll } from '../services/match-live-db';
import {
  forwardMatchResultToSite,
  resolveMatchForLiveRow,
  wasMatchResultForwarded,
} from '../services/match-result-forwarder';
import { siteRequestBaseUrl, siteSyncKeyFromEnv } from '../services/site-http';

async function main(): Promise<void> {
  const dryRun = process.argv.includes('--dry-run');
  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();

  console.log('=== Replay pending match results ===');
  console.log(`CLUTCH_SITE_URL (public): ${process.env.CLUTCH_SITE_URL?.trim() ?? '(not set)'}`);
  console.log(`CLUTCH_SITE_INTERNAL_URL: ${process.env.CLUTCH_SITE_INTERNAL_URL?.trim() ?? '(not set — using public URL)'}`);
  console.log(`Request base: ${base ?? '(not set)'}`);
  console.log(`CSGO_SKINS_SYNC_KEY: ${key ? 'set' : 'MISSING'}`);
  console.log(`dry-run: ${dryRun}`);
  console.log('');

  if (!base || !key) {
    console.error('Set CLUTCH_SITE_URL and CSGO_SKINS_SYNC_KEY in api-csgo/.env');
    process.exit(1);
  }

  const rows = listFinishedMatchLiveRowsAll(30);
  if (rows.length === 0) {
    console.log('No finished rows in clutch_match_live.');
    return;
  }

  let attempted = 0;
  let forwarded = 0;
  let skipped = 0;
  let noStore = 0;

  for (const row of rows) {
    if (wasMatchResultForwarded(row.matchId)) {
      skipped += 1;
      continue;
    }

    const match = resolveMatchForLiveRow(row);
    if (!match) {
      noStore += 1;
      console.log(`skip ${row.matchId}: not in store.json (orphan SQLite row)`);
      continue;
    }

    attempted += 1;
    console.log(
      `forward ${row.matchId} → room ${match.roomId} score ${row.scoreTeamA}:${row.scoreTeamB}`,
    );

    if (dryRun) continue;

    const ok = await forwardMatchResultToSite(match, row);
    if (ok) forwarded += 1;
  }

  console.log('');
  console.log(
    `done: ${forwarded} forwarded, ${attempted - forwarded} failed, ${skipped} already sent, ${noStore} orphan SQLite rows`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
