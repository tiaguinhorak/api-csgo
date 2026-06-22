/** kgns weapons.smx SQLite column names (without weapon_ prefix). */
export const WEAPON_ID_TO_DB_COLUMN: Record<string, string> = {
  weapon_awp: 'awp',
  weapon_ak47: 'ak47',
  weapon_m4a1: 'm4a1',
  weapon_m4a1_silencer: 'm4a1_silencer',
  weapon_deagle: 'deagle',
  weapon_usp_silencer: 'usp_silencer',
  weapon_hkp2000: 'hkp2000',
  weapon_glock: 'glock',
  weapon_elite: 'elite',
  weapon_p250: 'p250',
  weapon_cz75a: 'cz75a',
  weapon_fiveseven: 'fiveseven',
  weapon_tec9: 'tec9',
  weapon_revolver: 'revolver',
  weapon_nova: 'nova',
  weapon_xm1014: 'xm1014',
  weapon_mag7: 'mag7',
  weapon_sawedoff: 'sawedoff',
  weapon_m249: 'm249',
  weapon_negev: 'negev',
  weapon_mp9: 'mp9',
  weapon_mac10: 'mac10',
  weapon_mp7: 'mp7',
  weapon_ump45: 'ump45',
  weapon_p90: 'p90',
  weapon_bizon: 'bizon',
  weapon_famas: 'famas',
  weapon_galilar: 'galilar',
  weapon_ssg08: 'ssg08',
  weapon_aug: 'aug',
  weapon_sg556: 'sg556',
  weapon_scar20: 'scar20',
  weapon_g3sg1: 'g3sg1',
  weapon_knife_karambit: 'knife_karambit',
  weapon_knife_m9_bayonet: 'knife_m9_bayonet',
  weapon_bayonet: 'bayonet',
  weapon_knife_survival_bowie: 'knife_survival_bowie',
  weapon_knife_butterfly: 'knife_butterfly',
  weapon_knife_flip: 'knife_flip',
  weapon_knife_push: 'knife_push',
  weapon_knife_tactical: 'knife_tactical',
  weapon_knife_falchion: 'knife_falchion',
  weapon_knife_gut: 'knife_gut',
  weapon_knife_ursus: 'knife_ursus',
  weapon_knife_gypsy_jackknife: 'knife_gypsy_jackknife',
  weapon_knife_stiletto: 'knife_stiletto',
  weapon_knife_widowmaker: 'knife_widowmaker',
  weapon_mp5sd: 'mp5sd',
  weapon_knife_css: 'knife_css',
  weapon_knife_cord: 'knife_cord',
  weapon_knife_canis: 'knife_canis',
  weapon_knife_outdoor: 'knife_outdoor',
  weapon_knife_skeleton: 'knife_skeleton',
  weapon_knife: 'bayonet',
};

/** All knife paintkit columns in kgns weapons table. */
export const KNIFE_DB_COLUMNS: string[] = [
  'knife_karambit',
  'knife_m9_bayonet',
  'bayonet',
  'knife_survival_bowie',
  'knife_butterfly',
  'knife_flip',
  'knife_push',
  'knife_tactical',
  'knife_falchion',
  'knife_gut',
  'knife_ursus',
  'knife_gypsy_jackknife',
  'knife_stiletto',
  'knife_widowmaker',
  'knife_css',
  'knife_cord',
  'knife_canis',
  'knife_outdoor',
  'knife_skeleton',
];

/** kgns g_WeaponClasses index for knife column. */
export const WEAPON_ID_TO_KNIFE_INDEX: Record<string, number> = {
  weapon_knife: 0,
  weapon_knife_karambit: 33,
  weapon_knife_m9_bayonet: 34,
  weapon_bayonet: 35,
  weapon_knife_survival_bowie: 36,
  weapon_knife_butterfly: 37,
  weapon_knife_flip: 38,
  weapon_knife_push: 39,
  weapon_knife_tactical: 40,
  weapon_knife_falchion: 41,
  weapon_knife_gut: 42,
  weapon_knife_ursus: 43,
  weapon_knife_gypsy_jackknife: 44,
  weapon_knife_stiletto: 45,
  weapon_knife_widowmaker: 46,
  weapon_knife_css: 48,
  weapon_knife_cord: 49,
  weapon_knife_canis: 50,
  weapon_knife_outdoor: 51,
  weapon_knife_skeleton: 52,
};

export type SyncWeaponPayload = {
  weaponId: string;
  paintkit: number;
  wear?: number;
  seed?: number;
  stattrak?: boolean;
  stattrakCount?: number;
  nametag?: string | null;
};

export type SyncLoadoutOptions = {
  /** Zero paintkit columns before applying (required when switching knife types). */
  clearKnifeSlot?: boolean;
  /** Explicit weapon ids to clear (unequip). */
  clearWeaponIds?: string[];
};

const WEAR_DEFAULT = 0.15;

export function weaponIdToDbColumn(weaponId: string): string | null {
  return WEAPON_ID_TO_DB_COLUMN[weaponId] ?? null;
}

export function isMeleeWeaponId(weaponId: string): boolean {
  const id = weaponId.toLowerCase();
  return id.includes('knife') || id.includes('bayonet');
}

export function isGlovesWeaponId(weaponId: string): boolean {
  const id = weaponId.toLowerCase();
  return id.includes('gloves') || id.includes('handwraps');
}

function clearColumnUpdates(column: string): string[] {
  return [
    `${column}=0`,
    `${column}_float=0`,
    `${column}_trak=0`,
    `${column}_seed=0`,
    `${column}_tag=''`,
  ];
}

export function buildPlayerLoadoutSql(
  tablePrefix: string,
  steamId: string,
  weapons: SyncWeaponPayload[],
  options?: SyncLoadoutOptions,
): { insertSql: string; updateSql: string } {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = `${tablePrefix}weapons`;

  const updates: string[] = [];

  if (options?.clearKnifeSlot) {
    for (const column of KNIFE_DB_COLUMNS) {
      updates.push(...clearColumnUpdates(column));
    }
    updates.push('knife=0');
  }

  for (const weaponId of options?.clearWeaponIds ?? []) {
    const column = weaponIdToDbColumn(weaponId);
    if (column) {
      updates.push(...clearColumnUpdates(column));
    }
    if (isMeleeWeaponId(weaponId)) {
      updates.push('knife=0');
    }
  }

  let knifeIndex: number | null = null;

  for (const w of weapons) {
    if (isGlovesWeaponId(w.weaponId)) continue;
    if (!w.paintkit || w.paintkit <= 0) continue;

    const column = weaponIdToDbColumn(w.weaponId);
    if (!column) continue;

    const wear = w.wear ?? WEAR_DEFAULT;
    const seed = w.seed ?? 0;
    const trak = w.stattrak ? 1 : 0;
    const tag = (w.nametag ?? '').replace(/'/g, "''");

    updates.push(`${column}=${w.paintkit}`);
    updates.push(`${column}_float=${wear.toFixed(4)}`);
    updates.push(`${column}_trak=${trak}`);
    updates.push(`${column}_seed=${seed}`);
    updates.push(`${column}_tag='${tag}'`);

    if (isMeleeWeaponId(w.weaponId)) {
      const idx = WEAPON_ID_TO_KNIFE_INDEX[w.weaponId];
      if (idx !== undefined) knifeIndex = idx;
    }
  }

  if (knifeIndex !== null) {
    updates.push(`knife=${knifeIndex}`);
  }

  const insertSql = `INSERT OR IGNORE INTO ${table} (steamid) VALUES ('${escapedSteam}')`;
  const updateSql =
    updates.length > 0
      ? `UPDATE ${table} SET ${updates.join(', ')} WHERE steamid='${escapedSteam}'`
      : '';

  return { insertSql, updateSql };
}
