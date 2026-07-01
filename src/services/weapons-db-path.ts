import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';

const SQLITE_REL = 'addons/sourcemod/data/sqlite';

function expandHome(filePath: string): string {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

export function getSourceModRoots(): string[] {
  const serverDirs = new Set<string>();
  const envDir = process.env.CSGO_SERVER_DIR?.trim();
  if (envDir) serverDirs.add(envDir);

  serverDirs.add('/home/csgo/server');
  serverDirs.add('/home/csgo/server/csgo');

  const roots: string[] = [];
  for (const dir of serverDirs) {
    const normalized = dir.replace(/\/+$/, '');
    roots.push(normalized);
    if (normalized.endsWith('/csgo')) {
      roots.push(normalized.slice(0, -5));
    } else {
      roots.push(path.join(normalized, 'csgo'));
    }
  }
  return [...new Set(roots.map((r) => path.resolve(r)))];
}

/** Resolve SQLite file path for a databases.cfg connection block. */
export function resolveFromDatabasesCfg(
  smRoot: string,
  connectionName: string,
): string | null {
  const cfgPath = path.join(smRoot, 'configs/databases.cfg');
  if (!fs.existsSync(cfgPath)) return null;

  const content = fs.readFileSync(cfgPath, 'utf8');
  const blockPattern = new RegExp(
    `"${connectionName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"\\s*\\{([\\s\\S]*?)\\}`,
    'i',
  );
  const blockMatch = content.match(blockPattern);
  if (!blockMatch) return null;

  const dbMatch = blockMatch[1].match(/"database"\s*"([^"]+)"/i);
  if (!dbMatch) return null;

  const dbName = dbMatch[1].trim();
  const fileName = dbName.endsWith('.sq3') ? dbName : `${dbName}.sq3`;
  return path.join(smRoot, 'data/sqlite', fileName);
}

function sqliteFileCandidatesForRoot(csgoRoot: string): string[] {
  const smRoot = path.join(csgoRoot, 'addons/sourcemod');
  const fromCfg = resolveFromDatabasesCfg(
    smRoot,
    process.env.WEAPONS_DB_CONNECTION?.trim() || 'storage-local',
  );
  const names = [
    'sourcemod-local',
    'local',
    'clientprefs-sqlite',
    'weapons',
  ];

  const paths: string[] = [];
  if (fromCfg) paths.push(path.resolve(fromCfg));

  for (const name of names) {
    paths.push(path.join(smRoot, 'data/sqlite', `${name}.sq3`));
  }

  // Legacy wrong assumption in early bridge docs
  paths.push(path.join(smRoot, 'data/sqlite/local.sq3'));

  return paths;
}

/** Candidate paths for kgns weapons storage-local SQLite DB. */
export function getWeaponsDbCandidates(): string[] {
  const candidates: string[] = [];

  const explicit = process.env.WEAPONS_DB_PATH?.trim();
  if (explicit) {
    candidates.push(path.resolve(expandHome(explicit)));
  }

  for (const root of getSourceModRoots()) {
    candidates.push(...sqliteFileCandidatesForRoot(root));
  }

  candidates.push('/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3');

  return [...new Set(candidates.map((p) => path.resolve(p)))];
}

function canOpenDatabase(filePath: string): boolean {
  try {
    fs.accessSync(filePath, fs.constants.R_OK | fs.constants.W_OK);
    const dir = path.dirname(filePath);
    fs.accessSync(dir, fs.constants.R_OK | fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

function hasWeaponsTable(filePath: string): boolean {
  try {
    const conn = new Database(filePath, { readonly: true, fileMustExist: true });
    const prefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
    const table = `${prefix}weapons`;
    const row = conn
      .prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1`)
      .get(table) as { name?: string } | undefined;
    conn.close();
    return Boolean(row?.name);
  } catch {
    return false;
  }
}

export function resolveWeaponsDbPath(): string {
  const candidates = getWeaponsDbCandidates();
  const readable: string[] = [];
  let withWeaponsTable: string | null = null;

  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    readable.push(candidate);
    if (!canOpenDatabase(candidate)) continue;

    if (hasWeaponsTable(candidate)) {
      return candidate;
    }

    if (!withWeaponsTable) {
      withWeaponsTable = candidate;
    }
  }

  if (withWeaponsTable) {
    return withWeaponsTable;
  }

  if (readable.length > 0) {
    throw new Error(
      `SQLite found but not writable by api-csgo: ${readable[0]}. ` +
        'Run: chmod 664 file && chmod 775 directory (user csgo).',
    );
  }

  throw new Error(
    `Weapons SQLite not found. Set WEAPONS_DB_PATH in api-csgo .env. Tried: ${candidates.join(', ')}`,
  );
}

export function getWeaponsDbPath(): string {
  const explicit = process.env.WEAPONS_DB_PATH?.trim();
  if (explicit) {
    return path.resolve(expandHome(explicit));
  }
  return resolveWeaponsDbPath();
}

function hasMatchLiveTable(filePath: string): boolean {
  try {
    const conn = new Database(filePath, { readonly: true, fileMustExist: true });
    const row = conn
      .prepare(
        `SELECT name FROM sqlite_master WHERE type='table' AND name = 'clutch_match_live' LIMIT 1`,
      )
      .get() as { name?: string } | undefined;
    conn.close();
    return Boolean(row?.name);
  } catch {
    return false;
  }
}

function matchLiveRowCount(filePath: string): number {
  try {
    const conn = new Database(filePath, { readonly: true, fileMustExist: true });
    const row = conn
      .prepare(`SELECT COUNT(*) AS c FROM clutch_match_live`)
      .get() as { c: number };
    conn.close();
    return row.c ?? 0;
  } catch {
    return 0;
  }
}

/**
 * SQLite file used by clutch_match_tracker (clutch_match_db / storage-local).
 * On some VPS installs SourceMod writes connection-name.sq3 (storage-local.sq3)
 * while weapons live in sourcemod-local.sq3 — both must be checked.
 */
export function getMatchLiveDbPath(): string {
  const explicit = process.env.CLUTCH_MATCH_DB_PATH?.trim();
  if (explicit) {
    return path.resolve(expandHome(explicit));
  }

  const connectionName =
    process.env.CLUTCH_MATCH_DB_CONNECTION?.trim() || 'storage-local';
  const weaponsPath = getWeaponsDbPath();
  const sqliteDir = path.dirname(weaponsPath);
  const smRoot = path.resolve(sqliteDir, '..', '..');

  const candidates: string[] = [
    path.join(sqliteDir, `${connectionName}.sq3`),
  ];

  const fromCfg = resolveFromDatabasesCfg(smRoot, connectionName);
  if (fromCfg) {
    candidates.push(fromCfg);
  }

  candidates.push(weaponsPath);

  const unique = [...new Set(candidates.map((p) => path.resolve(p)))];
  let fallbackWithTable: string | null = null;

  for (const candidate of unique) {
    if (!fs.existsSync(candidate) || !canOpenDatabase(candidate)) continue;
    if (!hasMatchLiveTable(candidate)) continue;

    if (matchLiveRowCount(candidate) > 0) {
      return candidate;
    }

    if (!fallbackWithTable) {
      fallbackWithTable = candidate;
    }
  }

  if (fallbackWithTable) {
    return fallbackWithTable;
  }

  const byConnection = path.join(sqliteDir, `${connectionName}.sq3`);
  if (fs.existsSync(byConnection)) {
    return byConnection;
  }

  if (fromCfg && fs.existsSync(fromCfg)) {
    return fromCfg;
  }

  return weaponsPath;
}

/** All SQLite files that may hold clutch_match_live (multi-server installs). */
export function getMatchLiveDbCandidates(): string[] {
  const explicit = process.env.CLUTCH_MATCH_DB_PATH?.trim();
  if (explicit) {
    return [path.resolve(expandHome(explicit))];
  }

  const connectionName =
    process.env.CLUTCH_MATCH_DB_CONNECTION?.trim() || 'storage-local';
  const candidates = new Set<string>();

  for (const root of getSourceModRoots()) {
    const smRoot = path.join(root, 'addons/sourcemod');
    const sqliteDir = path.join(smRoot, 'data/sqlite');
    candidates.add(path.join(sqliteDir, `${connectionName}.sq3`));
    const fromCfg = resolveFromDatabasesCfg(smRoot, connectionName);
    if (fromCfg) candidates.add(fromCfg);
    candidates.add(path.join(sqliteDir, 'sourcemod-local.sq3'));
  }

  try {
    candidates.add(getWeaponsDbPath());
  } catch {
    // weapons db optional for candidate discovery
  }

  candidates.add(getMatchLiveDbPath());

  return [...candidates]
    .map((p) => path.resolve(p))
    .filter((p, index, all) => all.indexOf(p) === index)
    .filter((p) => fs.existsSync(p));
}
