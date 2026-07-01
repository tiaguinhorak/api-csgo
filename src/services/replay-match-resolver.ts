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

/**
 * Plugin SQLite match_id often differs from api-csgo store match id.
 * Match by overlapping player Steam IDs (same roster ≈ same ranked game).
 */
export function fuzzyMatchStoreForLiveRow(row: MatchLiveRow): Match | null {
  const rowSteams = sqliteSteamIds(row);
  if (rowSteams.size === 0) return null;

  let best: { match: Match; overlap: number } | null = null;

  for (const match of stateStore.matches.values()) {
    if (!isLikelyRankedSessionRoomId(match.roomId)) continue;

    const storeSteams = rosterSteamIds(match);
    if (storeSteams.size === 0) continue;

    const overlap = overlapCount(rowSteams, storeSteams);
    if (overlap === 0) continue;

    const minSize = Math.min(rowSteams.size, storeSteams.size);
    if (overlap / minSize < 0.5) continue;

    if (!best || overlap > best.overlap) {
      best = { match, overlap };
    }
  }

  return best?.match ?? null;
}

export function resolveMatchForReplay(row: MatchLiveRow): {
  match: Match;
  source: 'exact' | 'fuzzy';
} | null {
  const exact = stateStore.matches.get(row.matchId);
  if (exact && exact.status !== 'cancelled' && isLikelyRankedSessionRoomId(exact.roomId)) {
    return { match: exact, source: 'exact' };
  }

  const fuzzy = fuzzyMatchStoreForLiveRow(row);
  if (fuzzy) {
    return { match: fuzzy, source: 'fuzzy' };
  }

  if (exact && isLikelyRankedSessionRoomId(exact.roomId)) {
    return { match: exact, source: 'exact' };
  }

  return null;
}
