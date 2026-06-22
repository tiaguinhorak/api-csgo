import fs from 'fs';
import path from 'path';
import { GLOVE_WEAPON_ID_TO_DEFINDEX } from './weapons-db-map';
import { getSourceModRoots } from './weapons-db-path';

export type WsSkinAllowEntry = {
  weaponId: string;
  paintkit: number;
  name: string;
};

const DEFAULT_LANG = 'english';

function glovesCfgPath(smRoot: string, lang: string): string {
  return path.join(smRoot, 'configs/gloves', `gloves_${lang}.cfg`);
}

const DEFINDEX_TO_GLOVE_WEAPON_ID: Record<number, string> = Object.fromEntries(
  Object.entries(GLOVE_WEAPON_ID_TO_DEFINDEX).map(([weaponId, defIndex]) => [
    defIndex,
    weaponId,
  ]),
);

function parseGlovesCfg(content: string): WsSkinAllowEntry[] {
  const entries: WsSkinAllowEntry[] = [];
  let depth = 0;
  let gloveDefIndex: number | null = null;
  let pendingSkinName = '';

  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;

    const nameMatch = line.match(/^"([^"]+)"$/);
    if (nameMatch && !line.includes('{')) {
      pendingSkinName = nameMatch[1];
    }

    const indexMatch = line.match(/"index"\s+"(\d+)"/);
    if (indexMatch) {
      const index = Number(indexMatch[1]);
      if (!Number.isFinite(index) || index <= 0) continue;

      if (depth === 1) {
        gloveDefIndex = index;
      } else if (depth === 2 && gloveDefIndex !== null) {
        const weaponId = DEFINDEX_TO_GLOVE_WEAPON_ID[gloveDefIndex];
        if (weaponId) {
          entries.push({
            weaponId,
            paintkit: index,
            name: pendingSkinName || weaponId,
          });
        }
      }
    }

    if (line.includes('{')) depth += (line.match(/\{/g) ?? []).length;
    if (line.includes('}')) depth -= (line.match(/\}/g) ?? []).length;
  }

  return entries;
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

let cachedEntries: WsSkinAllowEntry[] | null = null;
let cachedAt = 0;
const CACHE_MS = 5 * 60 * 1000;

export function loadWsWeaponsAllowlist(force = false): {
  entries: WsSkinAllowEntry[];
  sourcePath: string | null;
  count: number;
} {
  const now = Date.now();
  if (!force && cachedEntries && now - cachedAt < CACHE_MS) {
    return {
      entries: cachedEntries,
      sourcePath: resolveWeaponsCfgFile()?.filePath ?? null,
      count: cachedEntries.length,
    };
  }

  const resolved = resolveWeaponsCfgFile();
  if (!resolved) {
    cachedEntries = [];
    cachedAt = now;
    return { entries: [], sourcePath: null, count: 0 };
  }

  const content = fs.readFileSync(resolved.filePath, 'utf8');
  const weaponEntries = parseWeaponsCfg(content);
  let gloveEntries: WsSkinAllowEntry[] = [];
  const glovesPath = glovesCfgPath(resolved.smRoot, process.env.WS_WEAPONS_LANG?.trim() || DEFAULT_LANG);
  if (fs.existsSync(glovesPath)) {
    gloveEntries = parseGlovesCfg(fs.readFileSync(glovesPath, 'utf8'));
  }
  cachedEntries = [...weaponEntries, ...gloveEntries];
  cachedAt = now;

  return {
    entries: cachedEntries,
    sourcePath: resolved.filePath,
    count: cachedEntries.length,
  };
}

export function isWsSkinAllowed(
  weaponId: string,
  paintkit: number,
  entries?: WsSkinAllowEntry[],
): boolean {
  const list = entries ?? loadWsWeaponsAllowlist().entries;
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
