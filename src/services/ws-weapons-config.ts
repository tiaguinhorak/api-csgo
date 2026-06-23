import fs from 'fs';
import path from 'path';
import { fetchWsAllowlistFromGithub } from './ws-allowlist-github';
import { fetchWsAllowlistFromSite } from './ws-allowlist-site';
import { parseGlovesCfgEntries } from './parse-gloves-cfg';
import { getSourceModRoots } from './weapons-db-path';

export type WsSkinAllowEntry = {
  weaponId: string;
  paintkit: number;
  name: string;
};

export type WsAllowlistSource = 'github' | 'vps-config' | 'all' | 'site-db';

const DEFAULT_LANG = 'english';

function glovesCfgPath(smRoot: string, lang: string): string {
  return path.join(smRoot, 'configs/gloves', `gloves_${lang}.cfg`);
}

function parseWeaponsCfg(content: string): WsSkinAllowEntry[] {
  const entries: WsSkinAllowEntry[] = [];
  const blockRe = /\t"([^"]+)"\s*\{([^}]*)\}/g;
  let match: RegExpExecArray | null;

  while ((match = blockRe.exec(content)) !== null) {
    const name = match[1].trim();
    const body = match[2];
    if (name === 'Skins') continue;

    const indexMatch = body.match(/"index"\s+"(\d+)"/);
    const classesMatch = body.match(/"classes"\s+"([^"]+)"/);
    if (!indexMatch || !classesMatch) continue;

    const paintkit = Number(indexMatch[1]);
    if (!Number.isFinite(paintkit) || paintkit <= 0) continue;

    const classes = classesMatch[1]
      .split(';')
      .map((c) => c.trim())
      .filter(Boolean);

    for (const weaponId of classes) {
      entries.push({ weaponId, paintkit, name });
    }
  }

  return entries;
}

function weaponsCfgPath(smRoot: string, lang: string): string {
  return path.join(smRoot, 'configs/weapons', `weapons_${lang}.cfg`);
}

function resolveWeaponsCfgFile(): { filePath: string; smRoot: string } | null {
  const lang = process.env.WS_WEAPONS_LANG?.trim() || DEFAULT_LANG;

  for (const root of getSourceModRoots()) {
    const smRoot = path.join(root, 'addons/sourcemod');
    const filePath = weaponsCfgPath(smRoot, lang);
    if (fs.existsSync(filePath)) {
      return { filePath, smRoot };
    }
  }

  return null;
}

export function resolveWsAllowlistSource(): WsAllowlistSource {
  const raw = process.env.WS_ALLOWLIST_SOURCE?.trim().toLowerCase() ?? 'github';
  if (raw === 'vps-config' || raw === 'vps' || raw === 'local') {
    return 'vps-config';
  }
  if (raw === 'all' || raw === 'none' || raw === 'off') {
    return 'all';
  }
  if (raw === 'site-db' || raw === 'site') {
    return 'site-db';
  }
  return 'github';
}

let cachedEntries: WsSkinAllowEntry[] | null = null;
let cachedSource: WsAllowlistSource | null = null;
let cachedSourcePath: string | null = null;
let cachedAt = 0;
const CACHE_MS = 5 * 60 * 1000;

function loadWsWeaponsAllowlistFromVps(): {
  entries: WsSkinAllowEntry[];
  sourcePath: string | null;
} {
  const resolved = resolveWeaponsCfgFile();
  if (!resolved) {
    return { entries: [], sourcePath: null };
  }

  const content = fs.readFileSync(resolved.filePath, 'utf8');
  const weaponEntries = parseWeaponsCfg(content);
  let gloveEntries: WsSkinAllowEntry[] = [];
  const glovesPath = glovesCfgPath(
    resolved.smRoot,
    process.env.WS_WEAPONS_LANG?.trim() || DEFAULT_LANG,
  );
  if (fs.existsSync(glovesPath)) {
    gloveEntries = parseGlovesCfgEntries(fs.readFileSync(glovesPath, 'utf8')).map((e) => ({
      weaponId: e.weaponId,
      paintkit: e.paintkit,
      name: e.name ?? e.weaponId,
    }));
  }

  return {
    entries: [...weaponEntries, ...gloveEntries],
    sourcePath: resolved.filePath,
  };
}

export async function loadWsWeaponsAllowlist(force = false): Promise<{
  entries: WsSkinAllowEntry[];
  source: WsAllowlistSource;
  sourcePath: string | null;
  count: number;
}> {
  const now = Date.now();
  const source = resolveWsAllowlistSource();

  if (
    !force &&
    cachedEntries &&
    cachedSource === source &&
    now - cachedAt < CACHE_MS
  ) {
    return {
      entries: cachedEntries,
      source,
      sourcePath: cachedSourcePath,
      count: cachedEntries.length,
    };
  }

  if (source === 'all') {
    cachedEntries = [];
    cachedSource = source;
    cachedSourcePath = null;
    cachedAt = now;
    return { entries: [], source, sourcePath: null, count: 0 };
  }

  if (source === 'site-db') {
    try {
      cachedEntries = await fetchWsAllowlistFromSite();
      cachedSource = source;
      cachedSourcePath = `site:${process.env.CLUTCH_SITE_URL ?? 'CLUTCH_SITE_URL'}/api/csgo/catalog/allowlist`;
      cachedAt = now;
      return {
        entries: cachedEntries,
        source,
        sourcePath: cachedSourcePath,
        count: cachedEntries.length,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[ws-allowlist] site-db fetch failed: ${message}`);
      cachedEntries = [];
      cachedSource = source;
      cachedSourcePath = null;
      cachedAt = now;
      return { entries: [], source, sourcePath: null, count: 0 };
    }
  }

  if (source === 'github') {
    const lang = process.env.WS_WEAPONS_LANG?.trim() || DEFAULT_LANG;
    try {
      cachedEntries = await fetchWsAllowlistFromGithub(lang);
      cachedSource = source;
      cachedSourcePath = `github:kgns/weapons+kgns/gloves (${lang})`;
      cachedAt = now;
      return {
        entries: cachedEntries,
        source,
        sourcePath: cachedSourcePath,
        count: cachedEntries.length,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[ws-allowlist] GitHub fetch failed: ${message} — trying VPS configs`);
      const vps = loadWsWeaponsAllowlistFromVps();
      cachedEntries = vps.entries;
      cachedSource = 'vps-config';
      cachedSourcePath = vps.sourcePath;
      cachedAt = now;
      return {
        entries: cachedEntries,
        source: 'vps-config',
        sourcePath: cachedSourcePath,
        count: cachedEntries.length,
      };
    }
  }

  const vps = loadWsWeaponsAllowlistFromVps();
  cachedEntries = vps.entries;
  cachedSource = source;
  cachedSourcePath = vps.sourcePath;
  cachedAt = now;

  return {
    entries: cachedEntries,
    source,
    sourcePath: cachedSourcePath,
    count: cachedEntries.length,
  };
}

export function isWsSkinAllowed(
  weaponId: string,
  paintkit: number,
  entries?: WsSkinAllowEntry[],
): boolean {
  const list = entries ?? cachedEntries ?? [];
  if (list.length === 0) return true;
  return list.some((e) => e.weaponId === weaponId && e.paintkit === paintkit);
}

export function wsAllowlistKey(weaponId: string, paintkit: number): string {
  return `${weaponId}:${paintkit}`;
}

export function buildWsAllowlistSet(entries: WsSkinAllowEntry[]): Set<string> {
  const set = new Set<string>();
  for (const e of entries) {
    set.add(wsAllowlistKey(e.weaponId, e.paintkit));
  }
  return set;
}

export function clearWsWeaponsAllowlistCache(): void {
  cachedEntries = null;
  cachedSource = null;
  cachedSourcePath = null;
  cachedAt = 0;
}
