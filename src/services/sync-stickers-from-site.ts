import type { StickerSyncEntry } from './stickers-db-map';
import { syncPlayerStickersToDb } from './stickers-db-sync';

type SiteStickerPayload = {
  steamId: string;
  entries: StickerSyncEntry[];
};

type SiteStickersResponse = {
  ok?: boolean;
  stickers?: SiteStickerPayload[];
};

function resolveSiteBaseUrl(): string | null {
  const raw =
    process.env.CLUTCH_SITE_URL?.trim() ||
    process.env.SITE_ORIGIN?.trim() ||
    '';
  if (!raw) return null;
  return raw.replace(/\/$/, '');
}

function resolveSkinsSyncKey(): string | null {
  const key = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  return key || null;
}

/**
 * Pull all player weapon stickers from site Postgres and write to local SQLite
 * (weaponstickers1 table — read by CSGO_WeaponStickers on spawn).
 */
export async function syncAllStickersFromSite(): Promise<{
  ok: boolean;
  synced: number;
  errors: string[];
  siteUrl: string | null;
}> {
  const siteUrl = resolveSiteBaseUrl();
  const syncKey = resolveSkinsSyncKey();

  if (!siteUrl || !syncKey) {
    return {
      ok: false,
      synced: 0,
      errors: ['CLUTCH_SITE_URL or SITE_ORIGIN and CSGO_SKINS_SYNC_KEY required'],
      siteUrl,
    };
  }

  const url = `${siteUrl}/api/csgo/stickers/equipped`;
  let stickers: SiteStickerPayload[] = [];

  try {
    const res = await fetch(url, {
      headers: {
        'x-skins-sync-key': syncKey,
        Accept: 'application/json',
      },
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      return {
        ok: false,
        synced: 0,
        errors: [`Site stickers API HTTP ${res.status}: ${text.slice(0, 200)}`],
        siteUrl,
      };
    }

    const data = (await res.json()) as SiteStickersResponse;
    stickers = data.stickers ?? [];
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'site fetch failed';
    return {
      ok: false,
      synced: 0,
      errors: [message],
      siteUrl,
    };
  }

  const errors: string[] = [];
  let synced = 0;

  for (const row of stickers) {
    if (!row?.steamId || !Array.isArray(row.entries)) {
      continue;
    }
    try {
      await syncPlayerStickersToDb(row.steamId, row.entries);
      synced += 1;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'sticker sync failed';
      errors.push(`${row.steamId}: ${message}`);
    }
  }

  return {
    ok: errors.length === 0,
    synced,
    errors,
    siteUrl,
  };
}
