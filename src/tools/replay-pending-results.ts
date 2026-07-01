/**
 * Re-forward finished SQLite rows to the site (including stale/cancelled sessions).
 * Usage:
 *   npm run build && node dist/tools/replay-pending-results.js [--dry-run] [--replay-stale]
 */
import 'dotenv/config';
import { listFinishedMatchLiveRowsAll } from '../services/match-live-db';
import {
  forwardMatchResultToSite,
  wasMatchResultForwarded,
} from '../services/match-result-forwarder';
import {
  isLikelyRankedSessionRoomId,
  resolveMatchForReplay,
} from '../services/replay-match-resolver';
import { siteRequestBaseUrl, siteSyncKeyFromEnv } from '../services/site-http';

async function main(): Promise<void> {
  const dryRun = process.argv.includes('--dry-run');
  const replayStale = process.argv.includes('--replay-stale') || !process.argv.includes('--no-replay-stale');
  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();

  console.log('=== Replay pending match results ===');
  console.log(`CLUTCH_SITE_URL (public): ${process.env.CLUTCH_SITE_URL?.trim() ?? '(not set)'}`);
  console.log(`Request base: ${base ?? '(not set)'}`);
  console.log(`CSGO_SKINS_SYNC_KEY: ${key ? 'set' : 'MISSING'}`);
  console.log(`replayStale: ${replayStale}`);
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
  let unresolved = 0;
  let invalidRoom = 0;

  for (const row of rows) {
    if (wasMatchResultForwarded(row.matchId)) {
      skipped += 1;
      continue;
    }

    const resolved = resolveMatchForReplay(row);
    if (!resolved) {
      unresolved += 1;
      console.log(`skip ${row.matchId}: no store match (orphan — plugin id ≠ api-csgo, roster mismatch)`);
      continue;
    }

    const { match, source } = resolved;
    if (!isLikelyRankedSessionRoomId(match.roomId)) {
      invalidRoom += 1;
      console.log(
        `skip sqlite=${row.matchId} store=${match.id}: invalid roomId "${match.roomId}" (not a ranked session)`,
      );
      continue;
    }

    attempted += 1;
    console.log(
      `forward sqlite=${row.matchId} → store=${match.id} room=${match.roomId} (${source}) score ${row.scoreTeamA}:${row.scoreTeamB}`,
    );

    if (dryRun) continue;

    const ok = await forwardMatchResultToSite(match, row, {
      replayStale,
      trackForwardedIds: [row.matchId],
    });
    if (ok) forwarded += 1;
  }

  console.log('');
  console.log(
    `done: ${forwarded} synced, ${attempted - forwarded} failed, ${skipped} already sent, ${unresolved} orphan, ${invalidRoom} invalid roomId`,
  );
  if (attempted - forwarded > 0) {
    console.log('');
    console.log('If still session_not_found: session may be deleted on site, or roomId never existed.');
    console.log('Deploy site with replayStale support, then re-run with --replay-stale');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
