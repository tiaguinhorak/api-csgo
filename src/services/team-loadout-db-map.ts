import {
  isGlovesWeaponId,
  isMeleeWeaponId,
  type SyncWeaponPayload,
  WEAPON_ID_TO_KNIFE_INDEX,
} from './weapons-db-map';

export const TEAM_LOADOUT_TABLE = 'clutch_team_loadout';

export function buildEnsureTeamLoadoutTableSql(tablePrefix = ''): string {
  const table = `${tablePrefix}${TEAM_LOADOUT_TABLE}`;
  return `CREATE TABLE IF NOT EXISTS ${table} (
    steamid varchar(32) NOT NULL,
    team char(2) NOT NULL,
    weapon_id varchar(64) NOT NULL,
    paintkit int NOT NULL DEFAULT 0,
    wear real NOT NULL DEFAULT 0.15,
    seed int NOT NULL DEFAULT 0,
    stattrak int NOT NULL DEFAULT 0,
    stattrak_count int NOT NULL DEFAULT 0,
    nametag varchar(64) NOT NULL DEFAULT '',
    knife_index int NOT NULL DEFAULT -1,
    PRIMARY KEY (steamid, team, weapon_id)
  )`;
}

export function buildTeamLoadoutSyncSql(
  tablePrefix: string,
  steamId: string,
  weapons: SyncWeaponPayload[],
): string[] {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = `${tablePrefix}${TEAM_LOADOUT_TABLE}`;
  const statements: string[] = [
    `DELETE FROM ${table} WHERE steamid='${escapedSteam}'`,
  ];

  for (const w of weapons) {
    if (!w.team || w.team !== 'T' && w.team !== 'CT') continue;
    if (isGlovesWeaponId(w.weaponId)) continue;
    if (!w.paintkit || w.paintkit <= 0) continue;

    const wear = (w.wear ?? 0.15).toFixed(4);
    const seed = w.seed ?? 0;
    const trak = w.stattrak ? 1 : 0;
    const trakCount = w.stattrak ? (w.stattrakCount ?? 0) : 0;
    const tag = (w.nametag ?? '').replace(/'/g, "''");
    const knifeIndex = isMeleeWeaponId(w.weaponId)
      ? (WEAPON_ID_TO_KNIFE_INDEX[w.weaponId] ?? -1)
      : -1;
    const escapedWeapon = w.weaponId.replace(/'/g, "''");

    statements.push(
      `INSERT INTO ${table} (steamid, team, weapon_id, paintkit, wear, seed, stattrak, stattrak_count, nametag, knife_index)
       VALUES ('${escapedSteam}', '${w.team}', '${escapedWeapon}', ${w.paintkit}, ${wear}, ${seed}, ${trak}, ${trakCount}, '${tag}', ${knifeIndex})
       ON CONFLICT(steamid, team, weapon_id) DO UPDATE SET
         paintkit=excluded.paintkit, wear=excluded.wear, seed=excluded.seed,
         stattrak=excluded.stattrak, stattrak_count=excluded.stattrak_count,
         nametag=excluded.nametag, knife_index=excluded.knife_index`,
    );
  }

  return statements;
}
