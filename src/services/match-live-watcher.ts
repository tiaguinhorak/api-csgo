import fs from 'fs';
import path from 'path';
import type { Match } from '../models/match';
import {
  ensureMatchLiveTableWritable,
  readMatchLive,
  type MatchLiveRow,
} from './match-live-db';
import {
  forwardMatchResultToSite,
  wasMatchResultForwarded,
} from './match-result-forwarder';
import { stateStore } from './state-store';
import { getMatchLiveDbPath } from './weapons-db-path';

type Snapshot = {
  phase: string;
  scoreTeamA: number;
  scoreTeamB: number;
  roundNum: number;
  finishedAt: number;
};

const lastSnapshots = new Map<string, Snapshot>();
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let watcherStarted = false;

import { siteBaseUrlFromEnv, siteRequestHeaders, siteSyncKeyFromEnv } from './site-http';

async function pushLiveRoundToSite(match: Match, row: MatchLiveRow): Promise<void> {
  const base = siteBaseUrlFromEnv();
  const key = siteSyncKeyFromEnv();
  if (!base || !key) return;

  try {
    const res = await fetch(`${base}/api/csgo/match-live`, {
      method: 'POST',
      headers: siteRequestHeaders({
        'content-type': 'application/json',
      }),
      body: JSON.stringify({
        csgoMatchId: match.id,
        roomId: match.roomId,
        scoreTeamA: row.scoreTeamA,
        scoreTeamB: row.scoreTeamB,
        round: row.roundNum,
        phase: row.phase,
      }),
      signal: AbortSignal.timeout(8_000),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.warn(`[match-live] live webhook ${res.status}: ${text.slice(0, 120)}`);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-live] live webhook failed: ${message}`);
  }
}

function snapshotFromRow(row: MatchLiveRow): Snapshot {
  return {
    phase: row.phase,
    scoreTeamA: row.scoreTeamA,
    scoreTeamB: row.scoreTeamB,
    roundNum: row.roundNum,
    finishedAt: row.finishedAt,
  };
}

function rowChanged(prev: Snapshot | undefined, row: MatchLiveRow): boolean {
  if (!prev) return true;
  return (
    prev.phase !== row.phase ||
    prev.scoreTeamA !== row.scoreTeamA ||
    prev.scoreTeamB !== row.scoreTeamB ||
    prev.roundNum !== row.roundNum ||
    prev.finishedAt !== row.finishedAt
  );
}

export async function processMatchLiveDbChanges(): Promise<void> {
  const liveMatches = Array.from(stateStore.matches.values()).filter(
    (m) => m.status === 'live',
  );
  if (!liveMatches.length) return;

  for (const match of liveMatches) {
    const row = readMatchLive(match.id);
    if (!row) continue;

    const prev = lastSnapshots.get(match.id);
    if (!rowChanged(prev, row)) continue;

    lastSnapshots.set(match.id, snapshotFromRow(row));

    if (row.phase === 'finished' && row.finishedAt > 0) {
      if (!wasMatchResultForwarded(match.id)) {
        await forwardMatchResultToSite(match, row);
      }

      if (match.status === 'live') {
        try {
          const { matchManager } = await import('./match-manager');
          const { serverManager } = await import('./server-manager');
          await matchManager.endMatch(match.id);
          if (match.serverId) {
            serverManager.releaseServer(match.serverId);
          }
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          console.warn(`[match-live] auto-release failed: ${message}`);
        }
      }

      continue;
    }

    if (row.phase === 'live' || row.phase === 'warmup') {
      await pushLiveRoundToSite(match, row);
    }
  }
}

function scheduleProcess(): void {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    void processMatchLiveDbChanges();
  }, 350);
}

export function startMatchLiveWatcher(): void {
  if (watcherStarted) return;
  watcherStarted = true;

  try {
    ensureMatchLiveTableWritable();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-live] table ensure skipped: ${message}`);
  }

  const dbPath = getMatchLiveDbPath();
  const watchDir = path.dirname(dbPath);
  const dbName = path.basename(dbPath);

  try {
    fs.watch(watchDir, (_event, filename) => {
      if (!filename) {
        scheduleProcess();
        return;
      }
      const name = filename.toString();
      if (name === dbName || name.startsWith(dbName)) {
        scheduleProcess();
      }
    });
    console.log(`[match-live] watching ${watchDir} (${dbName}*) for game events`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-live] fs.watch failed: ${message}`);
  }

  // Optional: api-csgo can also receive direct game webhooks (POST /api/matches/:id/game-event).
}

/** Called by HTTP webhook from game-event route (same path as SQLite watcher). */
export function notifyMatchLiveFromWebhook(matchId: string): void {
  const match = stateStore.matches.get(matchId);
  if (!match || match.status !== 'live') return;
  scheduleProcess();
}
