/** kgns weapon/glove lists from GitHub — no VPS config files required. */

import { parseGlovesCfgEntries } from './parse-gloves-cfg';
import type { WsSkinAllowEntry } from './ws-weapons-config';

const KGNS_WEAPONS_CFG =
  'https://raw.githubusercontent.com/kgns/weapons/master/addons/sourcemod/configs/weapons';
const KGNS_GLOVES_CFG =
  'https://raw.githubusercontent.com/kgns/gloves/master/addons/sourcemod/configs/gloves';

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
      gloveEntries = parseGlovesCfgEntries(await glovesRes.text()).map((e) => ({
        weaponId: e.weaponId,
        paintkit: e.paintkit,
        name: e.name ?? e.weaponId,
      }));
    }
  } catch {
    // gloves optional
  }

  return [...weaponEntries, ...gloveEntries];
}
