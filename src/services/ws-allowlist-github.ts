/** kgns weapon/glove lists from GitHub — no VPS config files required. */

import { GLOVE_WEAPON_ID_TO_DEFINDEX } from './weapons-db-map';
import type { WsSkinAllowEntry } from './ws-weapons-config';

const KGNS_WEAPONS_CFG =
  'https://raw.githubusercontent.com/kgns/weapons/master/addons/sourcemod/configs/weapons';
const KGNS_GLOVES_CFG =
  'https://raw.githubusercontent.com/kgns/gloves/master/addons/sourcemod/configs/gloves';

const DEFINDEX_TO_GLOVE_WEAPON_ID: Record<number, string> = Object.fromEntries(
  Object.entries(GLOVE_WEAPON_ID_TO_DEFINDEX).map(([weaponId, defIndex]) => [
    defIndex,
    weaponId,
  ]),
);

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

    for (const weaponId of classesMatch[1]
      .split(';')
      .map((c) => c.trim())
      .filter(Boolean)) {
      entries.push({ weaponId, paintkit, name });
    }
  }

  return entries;
}

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

export async function fetchWsAllowlistFromGithub(
  lang = 'english',
): Promise<WsSkinAllowEntry[]> {
  const weaponsUrl = `${KGNS_WEAPONS_CFG}/weapons_${lang}.cfg`;
  const glovesUrl = `${KGNS_GLOVES_CFG}/gloves_${lang}.cfg`;

  const weaponsRes = await fetch(weaponsUrl);
  if (!weaponsRes.ok) {
    throw new Error(`Failed to fetch weapons config (${weaponsRes.status})`);
  }

  const weaponEntries = parseWeaponsCfg(await weaponsRes.text());
  let gloveEntries: WsSkinAllowEntry[] = [];

  try {
    const glovesRes = await fetch(glovesUrl);
    if (glovesRes.ok) {
      gloveEntries = parseGlovesCfg(await glovesRes.text());
    }
  } catch {
    // gloves optional
  }

  return [...weaponEntries, ...gloveEntries];
}
