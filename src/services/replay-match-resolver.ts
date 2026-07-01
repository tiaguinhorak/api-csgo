import type { Match } from '../models/match';
import { parseMatchLivePayload, type MatchLiveRow } from './match-live-db';
import { stateStore } from './state-store';
import { normalizeSteamId64 } from '../utils/steam-id';

const SESSION_ROOM_ID = /^c[a-z0-9]{20,}$/i;

export function isLikelyRankedSessionRoomId(roomId: string): boolean {
  const trimmed = roomId.trim();
  if (!SESSION_ROOM_ID.test(trimmed)) return false;
  if (trimmed.includes('XXXX') || trimmed.includes('xxxx')) return false;
  if (trimmed.startsWith('STEAM_')) return false;
  return true;
}

function rosterSteamIds(match: Match): Set<string> {
  const ids = new Set<string>();
  for (const player of [...match.teamA.players, ...match.teamB.players]) {
    const normalized = normalizeSteamId64(player.steamId);
    if (normalized) ids.add(normalized);
  }
  return ids;
}

function sqliteSteamIds(row: MatchLiveRow): Set<string> {
  const live = parseMatchLivePayload(row.statsJson);
  const ids = new Set<string>();
  for (const player of live.players) {
    const normalized = normalizeSteamId64(player.steam);
    if (normalized) ids.add(normalized);
  }
  return ids;
}

function overlapCount(a: Set<string>, b: Set<string>): number {
  let count = 0;
  for (const id of a) {
    if (b.has(id)) count += 1;
  }
  return count;
}

function rowFinishedEpoch(row: MatchLiveRow): number {
  if (row.finishedAt > 0) return row.finishedAt;
  if (row.updatedAt > 0) return row.updatedAt;
  return 0;
}

function matchCreatedEpoch(match: Match): number {
  const parsed = Date.parse(match.createdAt);
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : 0;
}

type FuzzyCandidate = {
  match: Match;
  overlap: number;
  timeDeltaSec: number;
};

/**
 * Plugin SQLite match_id often differs from api-csgo store match id.
 * Match by roster overlap + closest createdAt (one store match per SQLite row).
 */
export function fuzzyMatchStoreForLiveRow(
  row: MatchLiveRow,
  excludeStoreMatchIds: ReadonlySet<string> = new Set(),
): Match | null {
  const rowSteams = sqliteSteamIds(row);
  if (rowSteams.size === 0) return null;

  const rowTime = rowFinishedEpoch(row);
  const candidates: FuzzyCandidate[] = [];

  for (const match of stateStore.matches.values()) {
    if (excludeStoreMatchIds.has(match.id)) continue;
    if (!isLikelyRankedSessionRoomId(match.roomId)) continue;

    const storeSteams = rosterSteamIds(match);
    if (storeSteams.size === 0) continue;

    const overlap = overlapCount(rowSteams, storeSteams);
    if (overlap === 0) continue;

    const minSize = Math.min(rowSteams.size, storeSteams.size);
    if (overlap / minSize < 0.5) continue;

    const matchTime = matchCreatedEpoch(match);
    const timeDeltaSec =
      rowTime > 0 && matchTime > 0 ? Math.abs(rowTime - matchTime) : Number.MAX_SAFE_INTEGER;

    candidates.push({ match, overlap, timeDeltaSec });
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => {
    if (b.overlap !== a.overlap) return b.overlap - a.overlap;
    return a.timeDeltaSec - b.timeDeltaSec;
  });

  return candidates[0]?.match ?? null;
}

export function resolveMatchForReplay(
  row: MatchLiveRow,
  excludeStoreMatchIds: ReadonlySet<string> = new Set(),
): {
  match: Match;
  source: 'exact' | 'fuzzy';
} | null {
  const exact = stateStore.matches.get(row.matchId);
  if (
    exact &&
    exact.status !== 'cancelled' &&
    isLikelyRankedSessionRoomId(exact.roomId) &&
    !excludeStoreMatchIds.has(exact.id)
  ) {
    return { match: exact, source: 'exact' };
  }

  const fuzzy = fuzzyMatchStoreForLiveRow(row, excludeStoreMatchIds);
  if (fuzzy) {
    return { match: fuzzy, source: 'fuzzy' };
  }

  if (
    exact &&
    isLikelyRankedSessionRoomId(exact.roomId) &&
    !excludeStoreMatchIds.has(exact.id)
  ) {
    return { match: exact, source: 'exact' };
  }

  return null;
}
