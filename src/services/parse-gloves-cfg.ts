/** Parse kgns gloves_*.cfg — glove type defindex (4xxx–5xxx) + paintkit (10000+). */

import { GLOVE_WEAPON_ID_TO_DEFINDEX } from './weapons-db-map';

const DEFINDEX_TO_GLOVE_WEAPON_ID: Record<number, string> = Object.fromEntries(
  Object.entries(GLOVE_WEAPON_ID_TO_DEFINDEX).map(([weaponId, defIndex]) => [
    defIndex,
    weaponId,
  ]),
);

export type GloveCfgEntry = {
  weaponId: string;
  paintkit: number;
  name?: string;
};

function isGloveTypeDefIndex(index: number): boolean {
  return index >= 4000 && index < 6000;
}

function isGlovePaintkit(index: number): boolean {
  return index >= 10000;
}

export function parseGlovesCfgEntries(content: string): GloveCfgEntry[] {
  const entries: GloveCfgEntry[] = [];
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

      if (isGloveTypeDefIndex(index)) {
        gloveDefIndex = index;
      } else if (isGlovePaintkit(index) && gloveDefIndex !== null) {
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
  }

  return entries;
}
