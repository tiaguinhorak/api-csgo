import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import os from 'os';
import {
  buildAgentLoadoutSql,
  buildEnsureAgentsTableSql,
  agentsTableName,
  type AgentSyncEntry,
} from './agents-db-map';
import { getWeaponsDbPath } from './weapons-db-path';
import { resolvePluginSteamIds } from './weapons-db-sync';

function expandHome(filePath: string): string {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

export function resolveAgentsDbPath(): string {
  const explicit = process.env.AGENTS_DB_PATH?.trim();
  if (explicit) {
    return path.resolve(expandHome(explicit));
  }
  return getWeaponsDbPath();
}

let agentsDb: Database.Database | null = null;
let resolvedAgentsDbPath: string | null = null;

function openAgentsDatabase(): Database.Database {
  if (agentsDb) return agentsDb;

  const dbPath = resolveAgentsDbPath();
  resolvedAgentsDbPath = dbPath;
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  agentsDb = new Database(dbPath);
  agentsDb.pragma('journal_mode = WAL');
  agentsDb.pragma('busy_timeout = 15000');
  return agentsDb;
}

export function logAgentsDbPath(): void {
  try {
    const dbPath = resolveAgentsDbPath();
    console.log(`[csgo-agents] agents DB resolved: ${dbPath}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[csgo-agents] agents DB not ready: ${message}`);
  }
}

export async function syncPlayerAgentsToDb(
  steamId: string,
  entries: AgentSyncEntry[],
): Promise<{
  steamId: string;
  steamIds: string[];
  updated: number;
  dbPath: string;
  table: string;
  rows: number;
}> {
  const db = openAgentsDatabase();
  const dbPath = resolvedAgentsDbPath ?? resolveAgentsDbPath();
  const tablePrefix = process.env.WS_TABLE_PREFIX?.trim() || '';
  const table = agentsTableName(tablePrefix);

  db.exec(buildEnsureAgentsTableSql(tablePrefix));

  const steamIds = resolvePluginSteamIds(steamId);
  let updated = 0;

  const tx = db.transaction(() => {
    for (const targetSteam of steamIds) {
      const statements = buildAgentLoadoutSql(tablePrefix, targetSteam, entries);
      for (const sql of statements) {
        db.exec(sql);
        updated += 1;
      }
    }
  });
  tx();

  db.pragma('wal_checkpoint(TRUNCATE)');

  const placeholders = steamIds.map(() => '?').join(',');
  const row = db
    .prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE steamid IN (${placeholders})`)
    .get(...steamIds) as { c: number };

  console.log(
    `[csgo-agents] synced ${entries.length} entries for ${steamIds.join(', ')} ` +
      `(${updated} sql ops) db=${dbPath} table=${table} rows=${row.c ?? 0}`,
  );

  return {
    steamId,
    steamIds,
    updated,
    dbPath,
    table,
    rows: row.c ?? 0,
  };
}

export function getResolvedAgentsDbPath(): string | null {
  return resolvedAgentsDbPath;
}
