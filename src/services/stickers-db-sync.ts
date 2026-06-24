import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import os from 'os';
import {
  buildEnsureClutchStickersTableSql,
  buildEnsureStickersTableSql,
  buildClutchStickerLoadoutSql,
  buildStickerLoadoutSql,
  clutchStickersTableName,
  stickersTableName,
  type StickerSyncEntry,
} from './stickers-db-map';
import { getWeaponsDbPath } from './weapons-db-path';
import { resolvePluginSteamIds } from './weapons-db-sync';

function expandHome(filePath: string): string {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

export function resolveStickersDbPath(): string {
  const explicit = process.env.STICKERS_DB_PATH?.trim();
  if (explicit) {
    return path.resolve(expandHome(explicit));
  }

  const weaponsPath = getWeaponsDbPath();
  return path.join(path.dirname(weaponsPath), 'csgo_weaponstickers.sq3');
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

function countRowsForSteam(
  db: Database.Database,
  table: string,
  steamIds: string[],
): number {
  if (steamIds.length === 0) return 0;
  const placeholders = steamIds.map(() => '?').join(',');
  const row = db
    .prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE steamid IN (${placeholders})`)
    .get(...steamIds) as { c: number };
  return row.c ?? 0;
}

export async function syncPlayerStickersToDb(
  steamId: string,
  entries: StickerSyncEntry[],
): Promise<{
  steamId: string;
  steamIds: string[];
  updated: number;
  dbPath: string;
  clutchTable: string;
  legacyTable: string;
  clutchRows: number;
  legacyRows: number;
}> {
  const db = openStickersDatabase();
  const dbPath = resolvedStickersDbPath ?? resolveStickersDbPath();
  const tablePrefix = process.env.STICKERS_TABLE_PREFIX?.trim() || '';
  const clutchTable = clutchStickersTableName(tablePrefix);
  const legacyTable = stickersTableName(tablePrefix);

  db.exec(buildEnsureStickersTableSql(tablePrefix));
  db.exec(buildEnsureClutchStickersTableSql(tablePrefix));

  const steamIds = resolvePluginSteamIds(steamId);
  let updated = 0;
  let clutchStmtCount = 0;
  let legacyStmtCount = 0;

  const tx = db.transaction(() => {
    for (const targetSteam of steamIds) {
      const legacyStatements = buildStickerLoadoutSql(tablePrefix, targetSteam, entries);
      const clutchStatements = buildClutchStickerLoadoutSql(tablePrefix, targetSteam, entries);
      legacyStmtCount += legacyStatements.length;
      clutchStmtCount += clutchStatements.length;
      for (const sql of [...legacyStatements, ...clutchStatements]) {
        db.exec(sql);
        updated += 1;
      }
    }
  });
  tx();

  db.pragma('wal_checkpoint(TRUNCATE)');

  const clutchRows = countRowsForSteam(db, clutchTable, steamIds);
  const legacyRows = countRowsForSteam(db, legacyTable, steamIds);

  console.log(
    `[csgo-stickers] synced ${entries.length} entries for ${steamIds.join(', ')} ` +
      `(${updated} sql ops, legacy stmts=${legacyStmtCount}, clutch stmts=${clutchStmtCount}) ` +
      `db=${dbPath} table=${clutchTable} rows=${clutchRows} (legacy ${legacyTable} rows=${legacyRows})`,
  );

  if (clutchStmtCount > 0 && clutchRows === 0) {
    console.error(
      `[csgo-stickers] WARN: clutch table ${clutchTable} still empty after sync — check schema/permissions on ${dbPath}`,
    );
  }

  return {
    steamId: steamIds[0],
    steamIds,
    updated,
    dbPath,
    clutchTable,
    legacyTable,
    clutchRows,
    legacyRows,
  };
}

export function logStickersDbPath(): void {
  try {
    const dbPath = resolveStickersDbPath();
    const prefix = process.env.STICKERS_TABLE_PREFIX?.trim() || '';
    console.log(
      `[csgo-stickers] DB resolved: ${dbPath} (clutch table: ${clutchStickersTableName(prefix)})`,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[csgo-stickers] DB path not resolved: ${message}`);
  }
}

export function closeStickersDatabase(): void {
  if (stickersDb) {
    stickersDb.close();
    stickersDb = null;
    resolvedStickersDbPath = null;
  }
}
