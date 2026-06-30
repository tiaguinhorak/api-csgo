import type { Match } from '../models/match';
import {
  parseMatchLivePayload,
  readMatchLive,
  type MatchLiveRow,
} from './match-live-db';

function siteBaseUrl(): string | null {
  const raw =
    process.env.CLUTCH_SITE_URL?.trim() ||
    process.env.SITE_ORIGIN?.trim() ||
    '';
  if (!raw) return null;
  return raw.replace(/\/+$/, '');
}

function syncKey(): string | null {
  const key = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  return key || null;
}

export type MatchResultPayload = {
  csgoMatchId: string;
  roomId: string;
  scoreTeamA: number;
  scoreTeamB: number;
  winnerTeam: string | null;
  durationSec: number;
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

function buildPayload(match: Match, row: MatchLiveRow): MatchResultPayload {
  const live = parseMatchLivePayload(row.statsJson);
  const players = live.players.map((p) => ({
    steamId: p.steam,
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

  if (players.some((p) => p.team !== 'A' && p.team !== 'B')) {
    const teamASteams = new Set(match.teamA.players.map((pl) => pl.steamId));
    for (const pl of players) {
      if (teamASteams.has(pl.steamId)) pl.team = 'A';
      else pl.team = 'B';
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
      victimSteamId: death.victimSteamId,
      killerSteamId: death.killerSteamId ?? null,
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
        steamId: hl.steamId,
        type: hl.type as 'ACE' | 'CLUTCH' | 'MULTI_KILL' | 'HEADSHOTS' | 'ENTRY' | 'KNIFE',
        roundNumber: hl.roundNumber,
        detail: hl.detail,
      }));
  }

  return payload;
}

const forwardedMatchIds = new Set<string>();

export function wasMatchResultForwarded(matchId: string): boolean {
  return forwardedMatchIds.has(matchId);
}

export async function forwardMatchResultToSite(match: Match, row: MatchLiveRow): Promise<boolean> {
  if (forwardedMatchIds.has(match.id)) return true;

  const base = siteBaseUrl();
  const key = syncKey();
  if (!base || !key) {
    console.warn('[match-live] CLUTCH_SITE_URL and CSGO_SKINS_SYNC_KEY required to forward results');
    return false;
  }

  const payload = buildPayload(match, row);
  const url = `${base}/api/csgo/match-result`;

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-skins-sync-key': key,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(12_000),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.warn(`[match-live] site forward ${res.status}: ${text.slice(0, 200)}`);
      return false;
    }

    forwardedMatchIds.add(match.id);
    console.log(`[match-live] forwarded result for match ${match.id}`);
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
