import Database from 'better-sqlite3';
import { getMatchLiveDbPath, getMatchLiveDbCandidates } from './weapons-db-path';

export type MatchLiveRow = {
  matchId: string;
  scoreTeamA: number;
  scoreTeamB: number;
  scoreCt: number;
  scoreT: number;
  roundNum: number;
  phase: string;
  winner: string;
  maxRounds: number;
  startedAt: number;
  finishedAt: number;
  statsJson: string;
  updatedAt: number;
};

export type MatchLivePlayerStat = {
  steam: string;
  slot: number;
  kills: number;
  deaths: number;
  assists: number;
  score: number;
  mvp: number;
  headshots?: number;
  damage?: number;
  awpKills?: number;
};

export type MatchLiveRound = {
  roundNumber: number;
  winnerTeam?: string | null;
  reason?: string | null;
  bombPlanted?: boolean;
};

export type MatchLiveDeath = {
  roundNumber?: number;
  victimSteamId: string;
  killerSteamId?: string | null;
  weapon?: string | null;
  headshot?: boolean;
  victimTeam?: string | null;
  x?: number;
  y?: number;
  z?: number;
};

export type MatchLiveHighlight = {
  steamId: string;
  type: string;
  roundNumber?: number;
  detail?: string;
};

export type MatchLivePayload = {
  players: MatchLivePlayerStat[];
  rounds: MatchLiveRound[];
  deaths: MatchLiveDeath[];
  highlights: MatchLiveHighlight[];
  demoFile?: string;
};

const TABLE = 'clutch_match_live';

function openReadonlyDb(dbPath: string): Database.Database {
  return new Database(dbPath, { readonly: true, fileMustExist: true });
}

export function ensureMatchLiveTableWritable(): void {
  const dbPath = getMatchLiveDbPath();
  const writable = new Database(dbPath);
  writable.exec(`
    CREATE TABLE IF NOT EXISTS ${TABLE} (
      match_id VARCHAR(64) PRIMARY KEY NOT NULL,
      score_team_a INTEGER NOT NULL DEFAULT 0,
      score_team_b INTEGER NOT NULL DEFAULT 0,
      score_ct INTEGER NOT NULL DEFAULT 0,
      score_t INTEGER NOT NULL DEFAULT 0,
      round_num INTEGER NOT NULL DEFAULT 0,
      phase VARCHAR(16) NOT NULL DEFAULT 'idle',
      winner VARCHAR(8) NOT NULL DEFAULT '',
      max_rounds INTEGER NOT NULL DEFAULT 30,
      started_at INTEGER NOT NULL DEFAULT 0,
      finished_at INTEGER NOT NULL DEFAULT 0,
      stats_json TEXT NOT NULL DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0
    )
  `);
  writable.close();
}

function mapRow(row: {
  match_id: string;
  score_team_a: number;
  score_team_b: number;
  score_ct: number;
  score_t: number;
  round_num: number;
  phase: string;
  winner: string;
  max_rounds: number;
  started_at: number;
  finished_at: number;
  stats_json: string;
  updated_at: number;
}): MatchLiveRow {
  return {
    matchId: row.match_id,
    scoreTeamA: row.score_team_a,
    scoreTeamB: row.score_team_b,
    scoreCt: row.score_ct,
    scoreT: row.score_t,
    roundNum: row.round_num,
    phase: row.phase,
    winner: row.winner,
    maxRounds: row.max_rounds,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    statsJson: row.stats_json ?? '',
    updatedAt: row.updated_at,
  };
}

export function readMatchLiveFromPath(dbPath: string, matchId: string): MatchLiveRow | null {
  try {
    const conn = openReadonlyDb(dbPath);
    try {
      const row = conn
        .prepare(
          `SELECT match_id, score_team_a, score_team_b, score_ct, score_t, round_num,
                  phase, winner, max_rounds, started_at, finished_at, stats_json, updated_at
           FROM ${TABLE} WHERE match_id = ? LIMIT 1`,
        )
        .get(matchId) as
        | {
            match_id: string;
            score_team_a: number;
            score_team_b: number;
            score_ct: number;
            score_t: number;
            round_num: number;
            phase: string;
            winner: string;
            max_rounds: number;
            started_at: number;
            finished_at: number;
            stats_json: string;
            updated_at: number;
          }
        | undefined;
      if (!row) return null;
      return mapRow(row);
    } finally {
      conn.close();
    }
  } catch {
    return null;
  }
}

export function readMatchLive(matchId: string): MatchLiveRow | null {
  for (const dbPath of getMatchLiveDbCandidates()) {
    const row = readMatchLiveFromPath(dbPath, matchId);
    if (row) return row;
  }
  return null;
}

export function listFinishedMatchLiveRows(dbPath: string, limit = 20): MatchLiveRow[] {
  try {
    const conn = openReadonlyDb(dbPath);
    try {
      const rows = conn
        .prepare(
          `SELECT match_id, score_team_a, score_team_b, score_ct, score_t, round_num,
                  phase, winner, max_rounds, started_at, finished_at, stats_json, updated_at
           FROM ${TABLE}
           WHERE phase = 'finished' AND finished_at > 0
           ORDER BY finished_at DESC
           LIMIT ?`,
        )
        .all(limit) as Array<{
          match_id: string;
          score_team_a: number;
          score_team_b: number;
          score_ct: number;
          score_t: number;
          round_num: number;
          phase: string;
          winner: string;
          max_rounds: number;
          started_at: number;
          finished_at: number;
          stats_json: string;
          updated_at: number;
        }>;
      return rows.map(mapRow);
    } finally {
      conn.close();
    }
  } catch {
    return [];
  }
}

export function listFinishedMatchLiveRowsAll(limitPerDb = 10): MatchLiveRow[] {
  const byMatchId = new Map<string, MatchLiveRow>();
  for (const dbPath of getMatchLiveDbCandidates()) {
    for (const row of listFinishedMatchLiveRows(dbPath, limitPerDb)) {
      const existing = byMatchId.get(row.matchId);
      if (!existing || row.finishedAt > existing.finishedAt) {
        byMatchId.set(row.matchId, row);
      }
    }
  }
  return [...byMatchId.values()].sort((a, b) => b.finishedAt - a.finishedAt);
}

function isPlayerStat(value: unknown): value is MatchLivePlayerStat {
  if (!value || typeof value !== 'object') return false;
  const row = value as MatchLivePlayerStat;
  return typeof row.steam === 'string' && row.steam.length > 4;
}

export function parseMatchLivePayload(statsJson: string): MatchLivePayload {
  if (!statsJson.trim()) {
    return { players: [], rounds: [], deaths: [], highlights: [] };
  }

  try {
    const parsed: unknown = JSON.parse(statsJson);
    if (Array.isArray(parsed)) {
      return {
        players: parsed.filter(isPlayerStat),
        rounds: [],
        deaths: [],
        highlights: [],
      };
    }

    if (parsed && typeof parsed === 'object') {
      const obj = parsed as {
        players?: unknown;
        rounds?: MatchLiveRound[];
        deaths?: MatchLiveDeath[];
        highlights?: MatchLiveHighlight[];
        demoFile?: unknown;
      };
      const players = Array.isArray(obj.players) ? obj.players.filter(isPlayerStat) : [];
      return {
        players,
        rounds: obj.rounds ?? [],
        deaths: obj.deaths ?? [],
        highlights: obj.highlights ?? [],
        demoFile: typeof obj.demoFile === 'string' && obj.demoFile.trim()
          ? obj.demoFile.trim()
          : undefined,
      };
    }
  } catch {
    return { players: [], rounds: [], deaths: [], highlights: [] };
  }

  return { players: [], rounds: [], deaths: [], highlights: [] };
}

/** @deprecated Use parseMatchLivePayload instead */
export function parseMatchLivePlayerStats(statsJson: string): MatchLivePlayerStat[] {
  return parseMatchLivePayload(statsJson).players;
}
