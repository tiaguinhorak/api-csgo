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

function getSourceModRoots(): string[] {
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

/** Read storage-local (or WEAPONS_DB_CONNECTION) database name from databases.cfg. */
function resolveFromDatabasesCfg(smRoot: string): string | null {
  const cfgPath = path.join(smRoot, 'configs/databases.cfg');
  if (!fs.existsSync(cfgPath)) return null;

  const connectionName =
    process.env.WEAPONS_DB_CONNECTION?.trim() || 'storage-local';
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
  const fromCfg = resolveFromDatabasesCfg(smRoot);
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
