import Database from 'better-sqlite3';
import { getWeaponsDbPath } from './weapons-db-path';

const TABLE = 'clutch_steam_allowlist';

function siteBaseUrl(): string {
  const raw = process.env.CLUTCH_SITE_URL?.trim();
  if (!raw) {
    throw new Error('CLUTCH_SITE_URL is required for steam allowlist sync');
  }
  return raw.replace(/\/$/, '');
}

function syncKey(): string {
  const key = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  if (!key) {
    throw new Error('CSGO_SKINS_SYNC_KEY is required for steam allowlist sync');
  }
  return key;
}

export async function fetchSteamAllowlistFromSite(): Promise<number[]> {
  const url = `${siteBaseUrl()}/api/csgo/steam-allowlist`;
  const res = await fetch(url, {
    headers: { 'x-skins-sync-key': syncKey() },
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Steam allowlist HTTP ${res.status}: ${text.slice(0, 200)}`);
  }

  const data = (await res.json()) as { accountIds?: number[] };
  if (!Array.isArray(data.accountIds)) {
    throw new Error('Steam allowlist response missing accountIds[]');
  }

  return data.accountIds.filter((id) => Number.isFinite(id) && id > 0);
}

export function ensureSteamAllowlistTable(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS ${TABLE} (
      account_id INTEGER PRIMARY KEY NOT NULL
    )
  `);
}

export function syncSteamAllowlistToDb(accountIds: number[]): number {
  const path = getWeaponsDbPath();
  const db = new Database(path);
  ensureSteamAllowlistTable(db);

  const insert = db.prepare(`INSERT OR REPLACE INTO ${TABLE} (account_id) VALUES (?)`);
  const trx = db.transaction((ids: number[]) => {
    db.exec(`DELETE FROM ${TABLE}`);
    for (const id of ids) {
      insert.run(id);
    }
  });
  trx(accountIds);
  db.close();
  return accountIds.length;
}

export async function runSteamAllowlistSync(): Promise<number> {
  const accountIds = await fetchSteamAllowlistFromSite();
  const count = syncSteamAllowlistToDb(accountIds);
  console.log(`[steam-allowlist] synced ${count} registered Steam account ids`);
  return count;
}

export function startSteamAllowlistSync(intervalMs = 5 * 60 * 1000): void {
  const run = () => {
    runSteamAllowlistSync().catch((err) => {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[steam-allowlist] sync failed: ${message}`);
    });
  };

  run();
  setInterval(run, intervalMs);
}
