import Database from 'better-sqlite3';
import {
  buildPlayerLoadoutSql,
  isMeleeWeaponId,
  type SyncLoadoutOptions,
  type SyncWeaponPayload,
} from './weapons-db-map';

const SQLITE_BUSY = 'SQLITE_BUSY';
const MAX_RETRIES = 8;
const BASE_RETRY_MS = 25;

let dbInstance: Database.Database | null = null;
let writeChain: Promise<void> = Promise.resolve();

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function alternateSteam2(steam2: string): string | null {
  const trimmed = steam2.trim();
  if (trimmed.startsWith('STEAM_0:')) return `STEAM_1:${trimmed.slice(8)}`;
  if (trimmed.startsWith('STEAM_1:')) return `STEAM_0:${trimmed.slice(8)}`;
  return null;
}

export function getWeaponsDbPath(): string {
  return (
    process.env.WEAPONS_DB_PATH?.trim() ||
    '/home/csgo/server/csgo/addons/sourcemod/data/sqlite/local.sq3'
  );
}

function getTableName(): string {
  const prefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
  return `${prefix}weapons`;
}

function openWeaponsDatabase(): Database.Database {
  if (dbInstance) return dbInstance;

  const path = getWeaponsDbPath();
  const db = new Database(path, {
    timeout: 15000,
    fileMustExist: true,
  });

  db.pragma('journal_mode = WAL');
  db.pragma('busy_timeout = 15000');
  db.pragma('synchronous = NORMAL');

  dbInstance = db;
  return db;
}

function enqueueWrite<T>(fn: () => Promise<T>): Promise<T> {
  const run = writeChain.then(() => fn());
  writeChain = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

function isBusyError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const code = (err as { code?: string }).code;
  return code === SQLITE_BUSY || code === 'SQLITE_LOCKED';
}

async function runWithRetryAsync<T>(fn: () => T): Promise<T> {
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      return fn();
    } catch (err) {
      if (!isBusyError(err) || attempt === MAX_RETRIES - 1) {
        throw err;
      }
      await sleep(BASE_RETRY_MS * (attempt + 1));
    }
  }
  throw new Error('SQLite retry exhausted');
}

function findExistingSteamRow(db: Database.Database, steamId: string): string | null {
  const table = getTableName();
  const candidates = [steamId.trim()];
  const alt = alternateSteam2(steamId);
  if (alt) candidates.push(alt);

  const stmt = db.prepare(`SELECT steamid FROM ${table} WHERE steamid = ? LIMIT 1`);

  for (const id of candidates) {
    const row = stmt.get(id) as { steamid?: string } | undefined;
    if (row?.steamid) return row.steamid;
  }
  return null;
}

function normalizeSyncOptions(
  weapons: SyncWeaponPayload[],
  options?: SyncLoadoutOptions,
): SyncLoadoutOptions {
  const normalized: SyncLoadoutOptions = { ...options };

  const hasMeleeEquipped = weapons.some(
    (w) => w.paintkit > 0 && isMeleeWeaponId(w.weaponId),
  );
  if (hasMeleeEquipped) {
    normalized.clearKnifeSlot = true;
  }

  return normalized;
}

export async function syncPlayerLoadoutToWeaponsDb(
  steamId: string,
  weapons: SyncWeaponPayload[],
  options?: SyncLoadoutOptions,
): Promise<{ steamId: string; updated: boolean; columns: number }> {
  return enqueueWrite(async () => {
    const db = openWeaponsDatabase();
    const tablePrefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
    const syncOptions = normalizeSyncOptions(weapons, options);

    const existing = findExistingSteamRow(db, steamId);
    const targetSteam = existing ?? steamId.trim();

    const { insertSql, updateSql } = buildPlayerLoadoutSql(
      tablePrefix,
      targetSteam,
      weapons,
      syncOptions,
    );

    const columnCount = updateSql ? updateSql.split(',').length : 0;

    await runWithRetryAsync(() => {
      const tx = db.transaction(() => {
        db.exec(insertSql);
        if (updateSql) {
          db.exec(updateSql);
        }
      });
      tx();
      return undefined;
    });

    return {
      steamId: targetSteam,
      updated: Boolean(updateSql),
      columns: columnCount,
    };
  });
}

export function closeWeaponsDatabase(): void {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}
