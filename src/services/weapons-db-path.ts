import fs from 'fs';
import os from 'os';
import path from 'path';

function expandHome(filePath: string): string {
  if (filePath.startsWith('~/')) {
    return path.join(os.homedir(), filePath.slice(2));
  }
  return filePath;
}

/** Candidate paths for kgns weapons storage-local SQLite DB. */
export function getWeaponsDbCandidates(): string[] {
  const candidates: string[] = [];

  const explicit = process.env.WEAPONS_DB_PATH?.trim();
  if (explicit) {
    candidates.push(path.resolve(expandHome(explicit)));
  }

  const serverDirs = new Set<string>();
  const envDir = process.env.CSGO_SERVER_DIR?.trim();
  if (envDir) serverDirs.add(envDir);

  serverDirs.add('/home/csgo/server');
  serverDirs.add('/home/csgo/server/csgo');

  for (const dir of serverDirs) {
    const normalized = dir.replace(/\/+$/, '');
    const roots = [normalized];
    if (normalized.endsWith('/csgo')) {
      roots.push(normalized.slice(0, -5));
    } else {
      roots.push(path.join(normalized, 'csgo'));
    }

    for (const root of roots) {
      candidates.push(
        path.join(root, 'addons/sourcemod/data/sqlite/local.sq3'),
        path.join(root, 'csgo/addons/sourcemod/data/sqlite/local.sq3'),
      );
    }
  }

  candidates.push('/home/csgo/server/csgo/addons/sourcemod/data/sqlite/local.sq3');

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

export function resolveWeaponsDbPath(): string {
  const candidates = getWeaponsDbCandidates();
  const readable: string[] = [];

  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    readable.push(candidate);
    if (canOpenDatabase(candidate)) {
      return candidate;
    }
  }

  if (readable.length > 0) {
    throw new Error(
      `Weapons DB exists but is not readable/writable by api-csgo: ${readable[0]}. ` +
        'Run: chmod 664 file && chmod 775 directory (same user as srcds).',
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
