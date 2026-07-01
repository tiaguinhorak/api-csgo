import fs from 'fs';
import path from 'path';
import type { Match } from '../models/match';
import {
  parseMatchLivePayload,
  type MatchLiveRow,
} from './match-live-db';
import { stateStore } from './state-store';
import { normalizeSteamId64 } from '../utils/steam-id';

import {
  siteRequestBaseUrl,
  siteRequestHeaders,
  siteSyncKeyFromEnv,
} from './site-http';
import { publishMatchDemo } from './match-demo-publisher';

export type MatchResultPayload = {
  csgoMatchId: string;
  roomId: string;
  scoreTeamA: number;
  scoreTeamB: number;
  winnerTeam: string | null;
  durationSec: number;
  replayStale?: boolean;
  demoUrl?: string | null;
  players: Array<{
    steamId: string;
    team: 'A' | 'B';
    kills: number;
    deaths: number;
    assists: number;
    score: number;
    mvp: number;
    headshots: number;
    damage: number;
    awpKills: number;
  }>;
  rounds?: Array<{
    roundNumber: number;
    winnerTeam?: string | null;
    reason?: string | null;
    bombPlanted?: boolean;
  }>;
  deaths?: Array<{
    roundNumber?: number;
    victimSteamId: string;
    killerSteamId?: string | null;
    weapon?: string | null;
    headshot?: boolean;
    victimTeam?: string | null;
    x?: number;
    y?: number;
    z?: number;
  }>;
  highlights?: Array<{
    steamId: string;
    type: 'ACE' | 'CLUTCH' | 'MULTI_KILL' | 'HEADSHOTS' | 'ENTRY' | 'KNIFE';
    roundNumber?: number;
    detail?: string;
  }>;
};

const dataDir = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const forwardedStorePath = path.join(dataDir, 'forwarded-match-results.json');

const forwardedMatchIds = new Set<string>();

function loadForwardedStore(): void {
  try {
    if (!fs.existsSync(forwardedStorePath)) return;
    const parsed = JSON.parse(fs.readFileSync(forwardedStorePath, 'utf8')) as unknown;
    if (!Array.isArray(parsed)) return;
    for (const id of parsed) {
      if (typeof id === 'string' && id.length > 0) {
        forwardedMatchIds.add(id);
      }
    }
  } catch {
    // ignore corrupt store
  }
}

function persistForwardedStore(): void {
  try {
    fs.mkdirSync(dataDir, { recursive: true });
    const ids = [...forwardedMatchIds].slice(-500);
    fs.writeFileSync(forwardedStorePath, JSON.stringify(ids, null, 2), 'utf8');
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-live] failed to persist forwarded store: ${message}`);
  }
}

loadForwardedStore();

function rosterHasSteam(roster: Match['teamA'], steamId: string): boolean {
  const normalized = normalizeSteamId64(steamId);
  return roster.players.some(
    (player) => normalizeSteamId64(player.steamId) === normalized,
  );
}

function buildPayload(match: Match, row: MatchLiveRow): MatchResultPayload {
  const live = parseMatchLivePayload(row.statsJson);
  const players = live.players.map((p) => ({
    steamId: normalizeSteamId64(p.steam),
    team: (p.slot === 1 ? 'A' : 'B') as 'A' | 'B',
    kills: p.kills ?? 0,
    deaths: p.deaths ?? 0,
    assists: p.assists ?? 0,
    score: p.score ?? 0,
    mvp: p.mvp ?? 0,
    headshots: p.headshots ?? 0,
    damage: p.damage ?? 0,
    awpKills: p.awpKills ?? 0,
  }));

  for (const pl of players) {
    if (rosterHasSteam(match.teamA, pl.steamId)) {
      pl.team = 'A';
    } else if (rosterHasSteam(match.teamB, pl.steamId)) {
      pl.team = 'B';
    }
  }

  let winnerTeam: string | null = row.winner || null;
  if (!winnerTeam) {
    if (row.scoreTeamA > row.scoreTeamB) winnerTeam = 'A';
    else if (row.scoreTeamB > row.scoreTeamA) winnerTeam = 'B';
  }

  const durationSec =
    row.finishedAt > 0 && row.startedAt > 0
      ? Math.max(0, row.finishedAt - row.startedAt)
      : 0;

  const payload: MatchResultPayload = {
    csgoMatchId: match.id,
    roomId: match.roomId,
    scoreTeamA: row.scoreTeamA,
    scoreTeamB: row.scoreTeamB,
    winnerTeam,
    durationSec,
    players,
  };

  if (live.rounds.length > 0) {
    payload.rounds = live.rounds.map((round) => ({
      roundNumber: round.roundNumber,
      winnerTeam: round.winnerTeam ?? null,
      reason: round.reason ?? null,
      bombPlanted: round.bombPlanted ?? false,
    }));
  }

  if (live.deaths.length > 0) {
    payload.deaths = live.deaths.map((death) => ({
      roundNumber: death.roundNumber ?? 0,
      victimSteamId: normalizeSteamId64(death.victimSteamId),
      killerSteamId: death.killerSteamId
        ? normalizeSteamId64(death.killerSteamId)
        : null,
      weapon: death.weapon ?? null,
      headshot: death.headshot ?? false,
      victimTeam: death.victimTeam ?? null,
      x: death.x ?? 0,
      y: death.y ?? 0,
      z: death.z ?? 0,
    }));
  }

  if (live.highlights.length > 0) {
    payload.highlights = live.highlights
      .filter((hl) =>
        ['ACE', 'CLUTCH', 'MULTI_KILL', 'HEADSHOTS', 'ENTRY', 'KNIFE'].includes(hl.type),
      )
      .map((hl) => ({
        steamId: normalizeSteamId64(hl.steamId),
        type: hl.type as 'ACE' | 'CLUTCH' | 'MULTI_KILL' | 'HEADSHOTS' | 'ENTRY' | 'KNIFE',
        roundNumber: hl.roundNumber,
        detail: hl.detail,
      }));
  }

  return payload;
}

export function wasMatchResultForwarded(matchId: string): boolean {
  return forwardedMatchIds.has(matchId);
}

export async function forwardMatchResultToSite(
  match: Match,
  row: MatchLiveRow,
  options: { replayStale?: boolean; trackForwardedIds?: string[] } = {},
): Promise<boolean> {
  if (forwardedMatchIds.has(match.id)) return true;

  if (row.phase !== 'finished' || row.finishedAt <= 0) {
    return false;
  }

  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();
  if (!base || !key) {
    console.warn('[match-live] CLUTCH_SITE_URL and CSGO_SKINS_SYNC_KEY required to forward results');
    return false;
  }

  const payload = buildPayload(match, row);
  if (payload.players.length === 0) {
    console.warn(`[match-live] skip forward ${match.id}: no player stats in SQLite payload`);
    return false;
  }

  if (options.replayStale) {
    payload.replayStale = true;
  }

  const live = parseMatchLivePayload(row.statsJson);
  const demoUrl = await publishMatchDemo(match.id, live.demoFile);
  if (demoUrl) {
    payload.demoUrl = demoUrl;
  }

  const url = `${base}/api/csgo/match-result`;

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: siteRequestHeaders({
        'content-type': 'application/json',
      }),
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(12_000),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.warn(
        `[match-live] site forward POST ${url} → ${res.status}: ${text.slice(0, 200)}`,
      );
      return false;
    }

    const body = (await res.json().catch(() => null)) as { skipped?: boolean } | null;
    forwardedMatchIds.add(match.id);
    for (const extraId of options.trackForwardedIds ?? []) {
      if (extraId) forwardedMatchIds.add(extraId);
    }
    persistForwardedStore();
    console.log(
      `[match-live] forwarded result for match ${match.id} → session ${match.roomId}` +
        (body?.skipped ? ' (already synced on site)' : ''),
    );
    return true;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-live] forward failed: ${message}`);
    return false;
  }
}

export async function pollLiveMatchesAndForward(): Promise<void> {
  const { processMatchLiveDbChanges } = await import('./match-live-watcher');
  await processMatchLiveDbChanges();
}

export function resolveMatchForLiveRow(row: MatchLiveRow): Match | null {
  const match = stateStore.matches.get(row.matchId);
  if (!match || match.status === 'cancelled') return null;
  return match;
}
