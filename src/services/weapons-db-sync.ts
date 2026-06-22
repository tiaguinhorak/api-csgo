import Database from 'better-sqlite3';
import {
  buildGlovesLoadoutSql,
  buildPlayerLoadoutSql,
  isMeleeWeaponId,
  type SyncLoadoutOptions,
  type SyncWeaponPayload,
} from './weapons-db-map';
import { resolveWeaponsDbPath } from './weapons-db-path';

const SQLITE_BUSY = 'SQLITE_BUSY';
const MAX_RETRIES = 8;
const BASE_RETRY_MS = 25;

let dbInstance: Database.Database | null = null;
let resolvedDbPath: string | null = null;
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

export function getActiveWeaponsDbPath(): string | null {
  return resolvedDbPath;
}

function getTableName(): string {
  const prefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
  return `${prefix}weapons`;
}

function openWeaponsDatabase(): Database.Database {
  if (dbInstance) return dbInstance;

  const dbPath = resolveWeaponsDbPath();
  resolvedDbPath = dbPath;

  try {
    const db = new Database(dbPath, {
      timeout: 15000,
      fileMustExist: true,
    });

    db.pragma('journal_mode = WAL');
    db.pragma('busy_timeout = 15000');
    db.pragma('synchronous = NORMAL');

    dbInstance = db;
    console.log(`[csgo-skins] weapons DB: ${dbPath}`);
    return db;
  } catch (err: unknown) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`unable to open database file (${dbPath}): ${detail}`);
  }
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

function steamIdVariants(steamId: string): string[] {
  const trimmed = steamId.trim();
  const alt = alternateSteam2(trimmed);
  const variants = alt ? [trimmed, alt] : [trimmed];
  return [...new Set(variants)];
}

function findExactSteamRow(db: Database.Database, steamId: string): string | null {
  const table = getTableName();
  const row = db
    .prepare(`SELECT steamid FROM ${table} WHERE steamid = ? LIMIT 1`)
    .get(steamId.trim()) as { steamid?: string } | undefined;
  return row?.steamid ?? null;
}

/** Both STEAM_0 and STEAM_1 rows must stay in sync — kgns and SourceMod use either format. */
function collectSteamIdsToUpdate(db: Database.Database, steamId: string): string[] {
  const ids = new Set<string>();
  for (const variant of steamIdVariants(steamId)) {
    ids.add(variant);
    const existing = findExactSteamRow(db, variant);
    if (existing) ids.add(existing);
  }
  return [...ids];
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

function ensureGlovesTable(db: Database.Database, tablePrefix: string): void {
  const table = `${tablePrefix}gloves`;
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${table} (
      steamid varchar(32) NOT NULL PRIMARY KEY,
      t_group int(5) NOT NULL DEFAULT 0,
      t_glove int(5) NOT NULL DEFAULT 0,
      t_float decimal(3,2) NOT NULL DEFAULT 0.0,
      ct_group int(5) NOT NULL DEFAULT 0,
      ct_glove int(5) NOT NULL DEFAULT 0,
      ct_float decimal(3,2) NOT NULL DEFAULT 0.0
    )`,
  );
}

export async function syncPlayerLoadoutToWeaponsDb(
  steamId: string,
  weapons: SyncWeaponPayload[],
  options?: SyncLoadoutOptions,
): Promise<{
  steamId: string;
  steamIds: string[];
  updated: boolean;
  columns: number;
  dbPath: string;
}> {
  return enqueueWrite(async () => {
    const db = openWeaponsDatabase();
    const dbPath = resolvedDbPath ?? resolveWeaponsDbPath();
    const tablePrefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
    const syncOptions = normalizeSyncOptions(weapons, options);

    const steamIds = collectSteamIdsToUpdate(db, steamId);
    let updated = false;
    let columnCount = 0;

    await runWithRetryAsync(() => {
      ensureGlovesTable(db, tablePrefix);
      const tx = db.transaction(() => {
        for (const targetSteam of steamIds) {
          const { insertSql, updateSql } = buildPlayerLoadoutSql(
            tablePrefix,
            targetSteam,
            weapons,
            syncOptions,
          );
          db.exec(insertSql);
          if (updateSql) {
            db.exec(updateSql);
            updated = true;
            columnCount = updateSql.split(',').length;
          }

          const glovesSql = buildGlovesLoadoutSql(
            tablePrefix,
            targetSteam,
            weapons,
            syncOptions.clearWeaponIds,
          );
          db.exec(glovesSql.insertSql);
          if (glovesSql.updateSql) {
            db.exec(glovesSql.updateSql);
            updated = true;
            columnCount += glovesSql.updateSql.split(',').length;
          }
        }
      });
      tx();
      return undefined;
    });

    if (steamIds.length > 1) {
      console.log(`[csgo-skins] synced loadout to ${steamIds.join(', ')}`);
    }

    return {
      steamId: steamIds[0],
      steamIds,
      updated,
      columns: columnCount,
      dbPath,
    };
  });
}

export function closeWeaponsDatabase(): void {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
    resolvedDbPath = null;
  }
}
