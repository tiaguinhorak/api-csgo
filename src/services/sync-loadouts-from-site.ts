import type { SyncWeaponPayload } from './weapons-db-map';
import { stageClutchLoadoutInGame } from './clutch-rcon';
import { syncAllStickersFromSite } from './sync-stickers-from-site';
import { syncPlayerLoadoutToWeaponsDb } from './weapons-db-sync';
import { siteRequestBaseUrl, siteRequestHeaders, siteSyncKeyFromEnv } from './site-http';

type SiteLoadoutPayload = {
  steamId: string;
  weapons: SyncWeaponPayload[];
};

type SiteLoadoutsResponse = {
  ok?: boolean;
  loadouts?: SiteLoadoutPayload[];
};

/**
 * Pull all equipped loadouts from the site Postgres (via site API) and write to
 * the local weapons SQLite — no clutch_skins.txt or SCP.
 */
export async function syncAllLoadoutsFromSite(): Promise<{
  ok: boolean;
  synced: number;
  stickersSynced: number;
  errors: string[];
  siteUrl: string | null;
  rconReload: boolean;
}> {
  const siteUrl = siteRequestBaseUrl();
  const syncKey = siteSyncKeyFromEnv();

  if (!siteUrl || !syncKey) {
    return {
      ok: false,
      synced: 0,
      stickersSynced: 0,
      errors: ['CLUTCH_SITE_URL or SITE_ORIGIN and CSGO_SKINS_SYNC_KEY required'],
      siteUrl,
      rconReload: false,
    };
  }

  const url = `${siteUrl}/api/csgo/skins/equipped-loadouts`;
  let loadouts: SiteLoadoutPayload[] = [];

  try {
    const res = await fetch(url, {
      headers: siteRequestHeaders({ Accept: 'application/json' }),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      return {
        ok: false,
        synced: 0,
        stickersSynced: 0,
        errors: [`Site API HTTP ${res.status}: ${text.slice(0, 200)}`],
        siteUrl,
        rconReload: false,
      };
    }

    const data = (await res.json()) as SiteLoadoutsResponse;
    loadouts = data.loadouts ?? [];
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'site fetch failed';
    return {
      ok: false,
      synced: 0,
      stickersSynced: 0,
      errors: [message],
      siteUrl,
      rconReload: false,
    };
  }

  const errors: string[] = [];
  let synced = 0;

  for (const row of loadouts) {
    if (!row?.steamId || !Array.isArray(row.weapons)) {
      continue;
    }
    try {
      await syncPlayerLoadoutToWeaponsDb(row.steamId, row.weapons);
      synced += 1;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'sync failed';
      errors.push(`${row.steamId}: ${message}`);
    }
  }

  const stickerResult = await syncAllStickersFromSite();
  for (const stickerError of stickerResult.errors) {
    errors.push(`stickers: ${stickerError}`);
  }

  const rconReload = synced > 0 ? await stageClutchLoadoutInGame() : false;

  return {
    ok: errors.length === 0,
    synced,
    stickersSynced: stickerResult.synced,
    errors,
    siteUrl,
    rconReload,
  };
}
