/** CSGO Weapon Stickers plugin — weaponstickers1 (legacy, no team). */
/** Clutch bridge — clutch_weaponstickers (per T/CT). */

export type StickerSyncEntry = {
  weaponIndex: number;
  team: "T" | "CT";
  slots: number[];
  wears?: number[];
};

export type StickerSyncPayload = {
  steamId: string;
  entries: StickerSyncEntry[];
};

export function stickersTableName(prefix = ""): string {
  return `${prefix}weaponstickers1`;
}

export function clutchStickersTableName(prefix = ""): string {
  return `${prefix}clutch_weaponstickers`;
}

function slotValues(entry: StickerSyncEntry) {
  const slots = entry.slots ?? [];
  const wears = entry.wears ?? [];
  return {
    s0: slots[0] ?? 0,
    s1: slots[1] ?? 0,
    s2: slots[2] ?? 0,
    s3: slots[3] ?? 0,
    s4: slots[4] ?? 0,
    s5: slots[5] ?? 0,
    w0: (wears[0] ?? 0).toFixed(6),
    w1: (wears[1] ?? 0).toFixed(6),
    w2: (wears[2] ?? 0).toFixed(6),
    w3: (wears[3] ?? 0).toFixed(6),
    w4: (wears[4] ?? 0).toFixed(6),
    w5: (wears[5] ?? 0).toFixed(6),
  };
}

export function buildClutchStickerLoadoutSql(
  tablePrefix: string,
  steamId: string,
  entries: StickerSyncEntry[],
): string[] {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = clutchStickersTableName(tablePrefix);
  const statements: string[] = [];

  for (const entry of entries) {
    if (!entry.weaponIndex || entry.weaponIndex <= 0) continue;
    const team = entry.team === "CT" ? "CT" : "T";
    const { s0, s1, s2, s3, s4, s5, w0, w1, w2, w3, w4, w5 } = slotValues(entry);
    const now = Math.floor(Date.now() / 1000);

    if (!s0 && !s1 && !s2 && !s3 && !s4 && !s5) {
      statements.push(
        `DELETE FROM ${table} WHERE steamid='${escapedSteam}' AND weaponindex=${entry.weaponIndex} AND team='${team}'`,
      );
      continue;
    }

    statements.push(
      `INSERT INTO ${table} (steamid, weaponindex, team, slot0, slot1, slot2, slot3, slot4, slot5, wear0, wear1, wear2, wear3, wear4, wear5, last_seen)
       VALUES ('${escapedSteam}', ${entry.weaponIndex}, '${team}', ${s0}, ${s1}, ${s2}, ${s3}, ${s4}, ${s5}, ${w0}, ${w1}, ${w2}, ${w3}, ${w4}, ${w5}, ${now})
       ON CONFLICT(steamid, weaponindex, team) DO UPDATE SET
         slot0=excluded.slot0, slot1=excluded.slot1, slot2=excluded.slot2, slot3=excluded.slot3, slot4=excluded.slot4, slot5=excluded.slot5,
         wear0=excluded.wear0, wear1=excluded.wear1, wear2=excluded.wear2, wear3=excluded.wear3, wear4=excluded.wear4, wear5=excluded.wear5,
         last_seen=excluded.last_seen`,
    );
  }

  return statements;
}

/** Legacy plugin table — last team wins if both sides synced; bridge uses clutch_weaponstickers. */
export function buildStickerLoadoutSql(
  tablePrefix: string,
  steamId: string,
  entries: StickerSyncEntry[],
): string[] {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = stickersTableName(tablePrefix);
  const statements: string[] = [];

  for (const entry of entries) {
    if (!entry.weaponIndex || entry.weaponIndex <= 0) continue;

    const { s0, s1, s2, s3, s4, s5, w0, w1, w2, w3, w4, w5 } = slotValues(entry);
    const now = Math.floor(Date.now() / 1000);

    if (!s0 && !s1 && !s2 && !s3 && !s4 && !s5) {
      statements.push(
        `DELETE FROM ${table} WHERE steamid='${escapedSteam}' AND weaponindex=${entry.weaponIndex}`,
      );
      continue;
    }

    statements.push(
      `INSERT INTO ${table} (steamid, weaponindex, slot0, slot1, slot2, slot3, slot4, slot5, wear0, wear1, wear2, wear3, wear4, wear5, last_seen)
       VALUES ('${escapedSteam}', ${entry.weaponIndex}, ${s0}, ${s1}, ${s2}, ${s3}, ${s4}, ${s5}, ${w0}, ${w1}, ${w2}, ${w3}, ${w4}, ${w5}, ${now})
       ON CONFLICT(steamid, weaponindex) DO UPDATE SET
         slot0=excluded.slot0, slot1=excluded.slot1, slot2=excluded.slot2, slot3=excluded.slot3, slot4=excluded.slot4, slot5=excluded.slot5,
         wear0=excluded.wear0, wear1=excluded.wear1, wear2=excluded.wear2, wear3=excluded.wear3, wear4=excluded.wear4, wear5=excluded.wear5,
         last_seen=excluded.last_seen`,
    );
  }

  return statements;
}

export function buildEnsureStickersTableSql(tablePrefix = ""): string {
  const table = stickersTableName(tablePrefix);
  return `CREATE TABLE IF NOT EXISTS ${table} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid varchar(64) NOT NULL,
    weaponindex int NOT NULL DEFAULT 0,
    slot0 int NOT NULL DEFAULT 0,
    slot1 int NOT NULL DEFAULT 0,
    slot2 int NOT NULL DEFAULT 0,
    slot3 int NOT NULL DEFAULT 0,
    slot4 int NOT NULL DEFAULT 0,
    slot5 int NOT NULL DEFAULT 0,
    wear0 real NOT NULL DEFAULT 0,
    wear1 real NOT NULL DEFAULT 0,
    wear2 real NOT NULL DEFAULT 0,
    wear3 real NOT NULL DEFAULT 0,
    wear4 real NOT NULL DEFAULT 0,
    wear5 real NOT NULL DEFAULT 0,
    rotation0 real NOT NULL DEFAULT 0,
    rotation1 real NOT NULL DEFAULT 0,
    rotation2 real NOT NULL DEFAULT 0,
    rotation3 real NOT NULL DEFAULT 0,
    rotation4 real NOT NULL DEFAULT 0,
    rotation5 real NOT NULL DEFAULT 0,
    last_seen int NOT NULL DEFAULT 0,
    UNIQUE(steamid, weaponindex)
  )`;
}

export function buildEnsureClutchStickersTableSql(tablePrefix = ""): string {
  const table = clutchStickersTableName(tablePrefix);
  return `CREATE TABLE IF NOT EXISTS ${table} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid varchar(64) NOT NULL,
    weaponindex int NOT NULL DEFAULT 0,
    team varchar(2) NOT NULL DEFAULT 'CT',
    slot0 int NOT NULL DEFAULT 0,
    slot1 int NOT NULL DEFAULT 0,
    slot2 int NOT NULL DEFAULT 0,
    slot3 int NOT NULL DEFAULT 0,
    slot4 int NOT NULL DEFAULT 0,
    slot5 int NOT NULL DEFAULT 0,
    wear0 real NOT NULL DEFAULT 0,
    wear1 real NOT NULL DEFAULT 0,
    wear2 real NOT NULL DEFAULT 0,
    wear3 real NOT NULL DEFAULT 0,
    wear4 real NOT NULL DEFAULT 0,
    wear5 real NOT NULL DEFAULT 0,
    last_seen int NOT NULL DEFAULT 0,
    UNIQUE(steamid, weaponindex, team)
  )`;
}
