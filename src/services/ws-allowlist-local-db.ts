/** Paintkits from equipped loadouts in local SQLite — ensures custom IDs appear in weapons_english.cfg */

import Database from 'better-sqlite3';
import { WEAPON_ID_TO_DB_COLUMN } from './weapons-db-map';
import { getWeaponsDbPath } from './weapons-db-path';
import type { WsSkinAllowEntry } from './ws-weapons-config';

const COLUMN_TO_WEAPON_ID: Record<string, string> = {};
for (const [weaponId, column] of Object.entries(WEAPON_ID_TO_DB_COLUMN)) {
  COLUMN_TO_WEAPON_ID[column] = weaponId;
}

function pushEntry(
  map: Map<string, WsSkinAllowEntry>,
  weaponId: string,
  paintkit: number,
  name?: string,
) {
  if (!weaponId || !Number.isFinite(paintkit) || paintkit <= 0) {
    return;
  }
  const key = `${weaponId}:${paintkit}`;
  if (map.has(key)) {
    return;
  }
  map.set(key, {
    weaponId,
    paintkit,
    name: name ?? `${weaponId} ${paintkit}`,
  });
}

export function fetchWsAllowlistFromLocalDb(): WsSkinAllowEntry[] {
  const map = new Map<string, WsSkinAllowEntry>();
  const dbPath = getWeaponsDbPath();
  const prefix = process.env.WEAPONS_TABLE_PREFIX?.trim() || '';
  const weaponsTable = `${prefix}weapons`;
  const teamTable = `${prefix}clutch_team_loadout`;

  const conn = new Database(dbPath, { readonly: true, fileMustExist: true });

  try {
    const weaponsExists = conn
      .prepare(
        `SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1`,
      )
      .get(weaponsTable) as { name?: string } | undefined;

    if (weaponsExists?.name) {
      const columns = Object.entries(COLUMN_TO_WEAPON_ID);
      for (const [column, weaponId] of columns) {
        const rows = conn
          .prepare(
            `SELECT DISTINCT ${column} AS paintkit FROM ${weaponsTable} WHERE ${column} > 0`,
          )
          .all() as Array<{ paintkit: number }>;
        for (const row of rows) {
          pushEntry(map, weaponId, row.paintkit);
        }
      }
    }

    const teamExists = conn
      .prepare(
        `SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1`,
      )
      .get(teamTable) as { name?: string } | undefined;

    if (teamExists?.name) {
      const rows = conn
        .prepare(
          `SELECT DISTINCT weapon_id, paintkit FROM ${teamTable} WHERE paintkit > 0`,
        )
        .all() as Array<{ weapon_id: string; paintkit: number }>;
      for (const row of rows) {
        pushEntry(map, row.weapon_id, row.paintkit);
      }
    }
  } finally {
    conn.close();
  }

  return [...map.values()];
}
