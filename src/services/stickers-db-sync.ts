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

function migrateLegacyStickersToClutch(
  db: Database.Database,
  tablePrefix: string,
  steamIds: string[],
): number {
  const legacyTable = stickersTableName(tablePrefix);
  const clutchTable = clutchStickersTableName(tablePrefix);
  if (countRowsForSteam(db, clutchTable, steamIds) > 0) {
    return 0;
  }

  const placeholders = steamIds.map(() => '?').join(',');
  const legacyRows = db
    .prepare(
      `SELECT steamid, weaponindex, slot0, slot1, slot2, slot3, slot4, slot5,
              wear0, wear1, wear2, wear3, wear4, wear5
       FROM ${legacyTable}
       WHERE steamid IN (${placeholders})
         AND (slot0 != 0 OR slot1 != 0 OR slot2 != 0 OR slot3 != 0 OR slot4 != 0 OR slot5 != 0)`,
    )
    .all(...steamIds) as Array<{
      steamid: string;
      weaponindex: number;
      slot0: number;
      slot1: number;
      slot2: number;
      slot3: number;
      slot4: number;
      slot5: number;
      wear0: number;
      wear1: number;
      wear2: number;
      wear3: number;
      wear4: number;
      wear5: number;
    }>;

  if (legacyRows.length === 0) return 0;

  const insert = db.prepare(
    `INSERT INTO ${clutchTable} (
       steamid, weaponindex, team,
       slot0, slot1, slot2, slot3, slot4, slot5,
       wear0, wear1, wear2, wear3, wear4, wear5
     ) VALUES (?, ?, 'T', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(steamid, weaponindex, team) DO UPDATE SET
       slot0=excluded.slot0, slot1=excluded.slot1, slot2=excluded.slot2,
       slot3=excluded.slot3, slot4=excluded.slot4, slot5=excluded.slot5,
       wear0=excluded.wear0, wear1=excluded.wear1, wear2=excluded.wear2,
       wear3=excluded.wear3, wear4=excluded.wear4, wear5=excluded.wear5`,
  );

  let migrated = 0;
  for (const row of legacyRows) {
    insert.run(
      row.steamid,
      row.weaponindex,
      row.slot0,
      row.slot1,
      row.slot2,
      row.slot3,
      row.slot4,
      row.slot5,
      row.wear0,
      row.wear1,
      row.wear2,
      row.wear3,
      row.wear4,
      row.wear5,
    );
    migrated += 1;
  }

  if (migrated > 0) {
    console.log(
      `[csgo-stickers] migrated ${migrated} legacy rows → ${clutchTable} (team T only)`,
    );
  }

  return migrated;
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

  let migrated = migrateLegacyStickersToClutch(db, tablePrefix, steamIds);

  db.pragma('wal_checkpoint(TRUNCATE)');

  const clutchRows = countRowsForSteam(db, clutchTable, steamIds);
  const legacyRows = countRowsForSteam(db, legacyTable, steamIds);

  console.log(
    `[csgo-stickers] synced ${entries.length} entries for ${steamIds.join(', ')} ` +
      `(${updated} sql ops, legacy stmts=${legacyStmtCount}, clutch stmts=${clutchStmtCount}, migrated=${migrated}) ` +
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
