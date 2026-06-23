import Database from 'better-sqlite3';
import { getWeaponsDbPath } from './weapons-db-path';

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
};

const TABLE = 'clutch_match_live';

let db: Database.Database | null = null;

function getDb(): Database.Database {
  if (!db) {
    const path = getWeaponsDbPath();
    db = new Database(path, { readonly: true, fileMustExist: true });
  }
  return db;
}

export function ensureMatchLiveTableWritable(): void {
  const path = getWeaponsDbPath();
  const writable = new Database(path);
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

export function readMatchLive(matchId: string): MatchLiveRow | null {
  try {
    const conn = getDb();
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
  } catch {
    return null;
  }
}

export function parseMatchLivePlayerStats(statsJson: string): MatchLivePlayerStat[] {
  if (!statsJson.trim()) return [];
  try {
    const parsed = JSON.parse(statsJson) as MatchLivePlayerStat[];
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (p) => typeof p.steam === 'string' && p.steam.length > 4,
    );
  } catch {
    return [];
  }
}
