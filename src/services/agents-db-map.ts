export type AgentSyncEntry = {
  team: 'T' | 'CT';
  defIndex: number;
  modelPath: string;
};

export type AgentSyncPayload = {
  steamId: string;
  entries: AgentSyncEntry[];
};

export function agentsTableName(prefix = ''): string {
  return `${prefix}clutch_agents`;
}

export function buildEnsureAgentsTableSql(tablePrefix = ''): string {
  const table = agentsTableName(tablePrefix);
  return `CREATE TABLE IF NOT EXISTS ${table} (
    steamid varchar(64) NOT NULL PRIMARY KEY,
    t_defindex int NOT NULL DEFAULT 0,
    ct_defindex int NOT NULL DEFAULT 0,
    t_model varchar(512) NOT NULL DEFAULT '',
    ct_model varchar(512) NOT NULL DEFAULT '',
    last_seen int NOT NULL DEFAULT 0
  )`;
}

export function buildAgentLoadoutSql(
  tablePrefix: string,
  steamId: string,
  entries: AgentSyncEntry[],
): string[] {
  const escapedSteam = steamId.replace(/'/g, "''");
  const table = agentsTableName(tablePrefix);
  const now = Math.floor(Date.now() / 1000);

  let tDef = 0;
  let ctDef = 0;
  let tModel = '';
  let ctModel = '';

  for (const entry of entries) {
    const model = entry.modelPath.replace(/'/g, "''");
    if (entry.team === 'T' && entry.defIndex > 0 && model) {
      tDef = entry.defIndex;
      tModel = model;
    }
    if (entry.team === 'CT' && entry.defIndex > 0 && model) {
      ctDef = entry.defIndex;
      ctModel = model;
    }
  }

  if (tDef <= 0 && ctDef <= 0) {
    return [`DELETE FROM ${table} WHERE steamid='${escapedSteam}'`];
  }

  return [
    `INSERT INTO ${table} (steamid, t_defindex, ct_defindex, t_model, ct_model, last_seen)
     VALUES ('${escapedSteam}', ${tDef}, ${ctDef}, '${tModel}', '${ctModel}', ${now})
     ON CONFLICT(steamid) DO UPDATE SET
       t_defindex=excluded.t_defindex,
       ct_defindex=excluded.ct_defindex,
       t_model=excluded.t_model,
       ct_model=excluded.ct_model,
       last_seen=excluded.last_seen`,
  ];
}
