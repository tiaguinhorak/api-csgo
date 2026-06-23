import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import {
  buildEnsureStickersTableSql,
  buildStickerLoadoutSql,
  type StickerSyncEntry,
} from './stickers-db-map';
import { resolvePluginSteamIds } from './weapons-db-sync';

function resolveStickersDbPath(): string {
  const explicit = process.env.STICKERS_DB_PATH?.trim();
  if (explicit) return explicit;

  const fromWeapons = process.env.WEAPONS_DB_PATH?.trim();
  if (fromWeapons) {
    // SourceMod SQLite driver: databases.cfg "database" "csgo_weaponstickers" → csgo_weaponstickers.sq3
    return path.join(path.dirname(fromWeapons), 'csgo_weaponstickers.sq3');
  }

  return '/home/csgo/server/csgo/addons/sourcemod/data/sqlite/csgo_weaponstickers.sq3';
}

let stickersDb: Database.Database | null = null;
let resolvedStickersDbPath: string | null = null;

function openStickersDatabase(): Database.Database {
  if (stickersDb) return stickersDb;

  const dbPath = resolveStickersDbPath();
  resolvedStickersDbPath = dbPath;
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  stickersDb = new Database(dbPath);
  stickersDb.pragma('journal_mode = WAL');
  stickersDb.pragma('busy_timeout = 15000');
  return stickersDb;
}

export async function syncPlayerStickersToDb(
  steamId: string,
  entries: StickerSyncEntry[],
): Promise<{ steamId: string; steamIds: string[]; updated: number; dbPath: string }> {
  const db = openStickersDatabase();
  const dbPath = resolvedStickersDbPath ?? resolveStickersDbPath();
  const tablePrefix = process.env.STICKERS_TABLE_PREFIX?.trim() || '';

  db.exec(buildEnsureStickersTableSql(tablePrefix));

  const steamIds = resolvePluginSteamIds(steamId);
  let updated = 0;

  const tx = db.transaction(() => {
    for (const targetSteam of steamIds) {
      const statements = buildStickerLoadoutSql(tablePrefix, targetSteam, entries);
      for (const sql of statements) {
        db.exec(sql);
        updated += 1;
      }
    }
  });
  tx();

  console.log(
    `[csgo-stickers] synced ${entries.length} weapon rows for ${steamIds.join(', ')} (${updated} sql ops)`,
  );

  return { steamId: steamIds[0], steamIds, updated, dbPath };
}

export function closeStickersDatabase(): void {
  if (stickersDb) {
    stickersDb.close();
    stickersDb = null;
    resolvedStickersDbPath = null;
  }
}
