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
import { siteRequestBaseUrl, siteRequestHeaders, siteSyncKeyFromEnv } from '../services/site-http';

type SessionLookup = {
  found: boolean;
  session?: {
    id: string;
    status: string;
    resultSyncedAt: string | null;
  } | null;
  hint?: string;
};

async function lookupSiteSession(
  base: string,
  roomId: string,
  csgoMatchId: string,
): Promise<SessionLookup | null> {
  const params = new URLSearchParams({ roomId, csgoMatchId });
  try {
    const res = await fetch(`${base}/api/csgo/ranked-session-lookup?${params}`, {
      headers: siteRequestHeaders(),
      signal: AbortSignal.timeout(8_000),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      if (res.status === 404 && text.includes('<!DOCTYPE')) {
        return null;
      }
      return { found: false, hint: `lookup HTTP ${res.status}` };
    }
    return (await res.json()) as SessionLookup;
  } catch {
    return null;
  }
}

async function main(): Promise<void> {
  const dryRun = process.argv.includes('--dry-run');
  const replayStale = process.argv.includes('--replay-stale') || !process.argv.includes('--no-replay-stale');
  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();

  console.log('=== Replay pending match results ===');
  console.log(`Request base: ${base ?? '(not set)'}`);
  console.log(`CSGO_SKINS_SYNC_KEY: ${key ? 'set' : 'MISSING'}`);
  console.log(`replayStale: ${replayStale}`);
  console.log(`dry-run: ${dryRun}`);
  console.log('');

  if (!base || !key) {
    console.error('Set CLUTCH_SITE_URL and CSGO_SKINS_SYNC_KEY in api-csgo/.env');
    process.exit(1);
  }

  const probeRes = await fetch(`${base}/api/csgo/ranked-session-lookup?roomId=__probe__`, {
    headers: siteRequestHeaders(),
    signal: AbortSignal.timeout(8_000),
  }).catch(() => null);

  if (!probeRes || probeRes.status === 404) {
    const text = probeRes ? await probeRes.text().catch(() => '') : '';
    if (!probeRes || text.includes('<!DOCTYPE')) {
      console.error('FAIL: site missing /api/csgo/ranked-session-lookup — deploy latest site first:');
      console.error('  cd ~/site && git pull && npm run build && pm2 restart site');
      process.exit(1);
    }
  }

  const rows = listFinishedMatchLiveRowsAll(30).sort(
    (a, b) => (b.finishedAt || b.updatedAt) - (a.finishedAt || a.updatedAt),
  );
  if (rows.length === 0) {
    console.log('No finished rows in clutch_match_live.');
    return;
  }

  let attempted = 0;
  let forwarded = 0;
  let skipped = 0;
  let unresolved = 0;
  let invalidRoom = 0;
  let noSiteSession = 0;
  const usedStoreMatchIds = new Set<string>();

  for (const row of rows) {
    if (wasMatchResultForwarded(row.matchId)) {
      skipped += 1;
      continue;
    }

    const resolved = resolveMatchForReplay(row, usedStoreMatchIds);
    if (!resolved) {
      unresolved += 1;
      console.log(`skip ${row.matchId}: no store match (orphan — roster mismatch)`);
      continue;
    }

    const { match, source } = resolved;
    if (!isLikelyRankedSessionRoomId(match.roomId)) {
      invalidRoom += 1;
      console.log(
        `skip sqlite=${row.matchId} store=${match.id}: invalid roomId "${match.roomId}"`,
      );
      continue;
    }

    const lookup = await lookupSiteSession(base, match.roomId, match.id);
    if (!lookup?.found) {
      noSiteSession += 1;
      console.log(
        `skip sqlite=${row.matchId} → room=${match.roomId} csgo=${match.id}: ${lookup?.hint ?? 'session not in site DB'}`,
      );
      continue;
    }

    if (lookup.session?.resultSyncedAt) {
      skipped += 1;
      console.log(`skip ${row.matchId}: already synced on site (${lookup.session.id})`);
      continue;
    }

    attempted += 1;
    console.log(
      `forward sqlite=${row.matchId} → store=${match.id} room=${match.roomId} (${source}) score ${row.scoreTeamA}:${row.scoreTeamB} site=${lookup.session?.status}`,
    );

    if (dryRun) {
      usedStoreMatchIds.add(match.id);
      continue;
    }

    const ok = await forwardMatchResultToSite(match, row, {
      replayStale,
      trackForwardedIds: [row.matchId],
    });
    if (ok) {
      forwarded += 1;
      usedStoreMatchIds.add(match.id);
    }
  }

  console.log('');
  console.log(
    `done: ${forwarded} synced, ${attempted - forwarded} failed, ${skipped} skipped, ${unresolved} orphan, ${invalidRoom} invalid room, ${noSiteSession} missing on site`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
