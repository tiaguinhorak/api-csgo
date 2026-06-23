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

};



/** kgns gloves.smx — glove type defindex (CSGO-API weapon.weapon_id). */

export const GLOVE_WEAPON_ID_TO_DEFINDEX: Record<string, number> = {

  studded_bloodhound_gloves: 5027,

  sporty_gloves: 5030,

  slick_gloves: 5031,

  leather_handwraps: 5032,

  motorcycle_gloves: 5033,

  specialist_gloves: 5034,

  studded_hydra_gloves: 5035,

  studded_brokenfang_gloves: 4725,

};



/** All knife paintkit columns in kgns weapons table (v1.7.8). */

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

  /** Glove type defindex from catalog (weapon.weapon_id). */

  defIndex?: number;

  /** Terrorist / CT — gloves sync per side; optional for weapons. */

  team?: "T" | "CT";

};



export type SyncLoadoutOptions = {

  /** Zero paintkit columns before applying (required when switching knife types). */

  clearKnifeSlot?: boolean;

  /** Explicit weapon ids to clear (unequip). */

  clearWeaponIds?: string[];

  /** Clear only one glove side (t_* or ct_* columns). */

  clearGloveTeam?: "T" | "CT";

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

/** Buy-menu team locks — shared weapons (Deagle, AWP, etc.) still use kgns columns. */
const T_ONLY_WEAPON_IDS = new Set([
  'weapon_glock',
  'weapon_tec9',
  'weapon_galilar',
  'weapon_ak47',
  'weapon_g3sg1',
  'weapon_mac10',
  'weapon_sawedoff',
]);

const CT_ONLY_WEAPON_IDS = new Set([
  'weapon_hkp2000',
  'weapon_usp_silencer',
  'weapon_fiveseven',
  'weapon_cz75a',
  'weapon_famas',
  'weapon_m4a1',
  'weapon_m4a1_silencer',
  'weapon_aug',
  'weapon_sg556',
  'weapon_scar20',
  'weapon_mp9',
  'weapon_mag7',
]);

export function isTeamExclusiveWeapon(weaponId: string): boolean {
  const id = weaponId.trim().toLowerCase();
  return T_ONLY_WEAPON_IDS.has(id) || CT_ONLY_WEAPON_IDS.has(id);
}



export function normalizeGloveWeaponId(weaponId: string): string {
  let id = weaponId.trim().toLowerCase();
  if (id.startsWith('weapon_')) {
    id = id.slice('weapon_'.length);
  }
  return id;
}

export function resolveGloveDefIndex(weaponId: string, defIndex?: number): number | null {
  if (defIndex !== undefined && defIndex > 0) {
    if (defIndex >= 4000 || defIndex === 4725) return defIndex;
  }

  const normalized = normalizeGloveWeaponId(weaponId);
  const mapped =
    GLOVE_WEAPON_ID_TO_DEFINDEX[normalized] ?? GLOVE_WEAPON_ID_TO_DEFINDEX[weaponId];

  if (mapped) return mapped;

  return null;
}



function clearColumnUpdates(column: string): string[] {

  return [

    `${column}=0`,

    `${column}_float=0`,

    `${column}_trak=0`,

    `${column}_trak_count=0`,

    `${column}_seed=0`,

    `${column}_tag=''`,

  ];

}

/** Zero entire kgns weapons row — web loadout uses clutch_team_loadout; stale !ws columns must not apply. */
export function buildResetKgnsWeaponsRowSql(tablePrefix: string, steamId: string): string {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = `${tablePrefix}weapons`;
  const updates: string[] = [];

  for (const column of Object.values(WEAPON_ID_TO_DB_COLUMN)) {
    updates.push(...clearColumnUpdates(column));
  }
  for (const column of KNIFE_DB_COLUMNS) {
    updates.push(...clearColumnUpdates(column));
  }
  updates.push('knife=0');

  return `UPDATE ${table} SET ${updates.join(', ')} WHERE steamid='${escapedSteam}'`;
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

    // Per-side paintkits: shared weapons → clutch_team_loadout only; team-exclusive → kgns + team table.
    if (w.team === 'T' || w.team === 'CT') {
      if (isMeleeWeaponId(w.weaponId)) {
        const teamColumn = weaponIdToDbColumn(w.weaponId);
        if (teamColumn) {
          updates.push(...clearColumnUpdates(teamColumn));
        }
        updates.push('knife=0');
        continue;
      }
      if (!isTeamExclusiveWeapon(w.weaponId)) {
        const sharedColumn = weaponIdToDbColumn(w.weaponId);
        if (sharedColumn) {
          updates.push(...clearColumnUpdates(sharedColumn));
        }
        continue;
      }
    }



    const column = weaponIdToDbColumn(w.weaponId);

    if (!column) continue;



    const wear = w.wear ?? WEAR_DEFAULT;

    const seed = w.seed ?? 0;

    const trak = w.stattrak ? 1 : 0;

    const trakCount = w.stattrak ? (w.stattrakCount ?? 0) : 0;

    const tag = (w.nametag ?? '').replace(/'/g, "''");



    updates.push(`${column}=${w.paintkit}`);

    updates.push(`${column}_float=${wear.toFixed(4)}`);

    updates.push(`${column}_trak=${trak}`);

    updates.push(`${column}_trak_count=${trakCount}`);

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



function glovesTableName(tablePrefix: string): string {

  return `${tablePrefix}gloves`;

}



export type GlovesLoadoutSqlResult = {
  insertSql: string;
  updateSql: string;
  action: "none" | "clear" | "apply" | "skipped";
  group?: number;
  paintkit?: number;
  weaponId?: string;
};

export function buildGlovesLoadoutSql(
  tablePrefix: string,
  steamId: string,
  weapons: SyncWeaponPayload[],
  options?: Pick<SyncLoadoutOptions, "clearWeaponIds" | "clearGloveTeam">,
): GlovesLoadoutSqlResult {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = glovesTableName(tablePrefix);
  const insertSql = `INSERT OR IGNORE INTO ${table} (steamid) VALUES ('${escapedSteam}')`;
  const clearWeaponIds = options?.clearWeaponIds ?? [];
  const clearGloveTeam = options?.clearGloveTeam;

  const tGlove = weapons.find(
    (w) => isGlovesWeaponId(w.weaponId) && w.paintkit > 0 && w.team === "T",
  );
  const ctGlove = weapons.find(
    (w) => isGlovesWeaponId(w.weaponId) && w.paintkit > 0 && w.team === "CT",
  );
  const legacyGlove = weapons.find(
    (w) => isGlovesWeaponId(w.weaponId) && w.paintkit > 0 && !w.team,
  );

  const effectiveT = tGlove ?? (!ctGlove ? legacyGlove : undefined);
  const effectiveCT = ctGlove ?? (!tGlove ? legacyGlove : undefined);

  const updates: string[] = [];

  if (!effectiveT) {
    updates.push('t_group=0', 't_glove=0', 't_float=0');
  }
  if (!effectiveCT) {
    updates.push('ct_group=0', 'ct_glove=0', 'ct_float=0');
  }

  const clearAllFromWeapons =
    clearWeaponIds.some((id) => isGlovesWeaponId(id)) &&
    !effectiveT &&
    !effectiveCT;

  if (clearAllFromWeapons && !clearGloveTeam) {
    const updateSql = `UPDATE ${table} SET t_group=0, t_glove=0, t_float=0, ct_group=0, ct_glove=0, ct_float=0 WHERE steamid='${escapedSteam}'`;
    return { insertSql, updateSql, action: "clear" };
  }

  if (clearGloveTeam === "T" && !effectiveT) {
    const updateSql = `UPDATE ${table} SET t_group=0, t_glove=0, t_float=0 WHERE steamid='${escapedSteam}'`;
    return { insertSql, updateSql, action: "clear" };
  }

  if (clearGloveTeam === "CT" && !effectiveCT) {
    const updateSql = `UPDATE ${table} SET ct_group=0, ct_glove=0, ct_float=0 WHERE steamid='${escapedSteam}'`;
    return { insertSql, updateSql, action: "clear" };
  }

  function applySide(
    side: "T" | "CT",
    glove: SyncWeaponPayload | undefined,
  ): { group?: number; paintkit?: number; weaponId?: string } {
    if (!glove) return {};
    const group = resolveGloveDefIndex(glove.weaponId, glove.defIndex);
    if (!group) {
      console.warn(
        `[csgo-skins] glove defindex unresolved for weaponId=${glove.weaponId} defIndex=${glove.defIndex ?? "n/a"} paintkit=${glove.paintkit}`,
      );
      return { weaponId: glove.weaponId, paintkit: glove.paintkit };
    }
    const wear = (glove.wear ?? WEAR_DEFAULT).toFixed(2);
    const paint = glove.paintkit;
    if (side === "T") {
      updates.push(`t_group=${group}`, `t_glove=${paint}`, `t_float=${wear}`);
    } else {
      updates.push(`ct_group=${group}`, `ct_glove=${paint}`, `ct_float=${wear}`);
    }
    return { group, paintkit: paint, weaponId: glove.weaponId };
  }

  const tMeta = applySide("T", effectiveT);
  const ctMeta = applySide("CT", effectiveCT);

  if (!updates.length) {
    return { insertSql, updateSql: "", action: "none" };
  }

  const updateSql = `UPDATE ${table} SET ${updates.join(", ")} WHERE steamid='${escapedSteam}'`;
  const appliedMeta = ctMeta.group ? ctMeta : tMeta;

  return {
    insertSql,
    updateSql,
    action: appliedMeta.group ? "apply" : "skipped",
    group: appliedMeta.group,
    paintkit: appliedMeta.paintkit,
    weaponId: appliedMeta.weaponId,
  };
}


