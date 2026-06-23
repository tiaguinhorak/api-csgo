import { Router, Request, Response } from 'express';
import { syncAllLoadoutsFromSite } from '../services/sync-loadouts-from-site';
import type { SyncWeaponPayload } from '../services/weapons-db-map';
import { syncPlayerLoadoutToWeaponsDb } from '../services/weapons-db-sync';
import {
  buildWsAllowlistSet,
  loadWsWeaponsAllowlist,
} from '../services/ws-weapons-config';
import { reloadClutchSkinsInGame, reloadWeaponsPluginInGame } from '../services/clutch-rcon';
import { syncWeaponsCfgFromSite } from '../services/sync-weapons-cfg-file';
import { filterCsgoCompatibleWeapons } from '../services/paintkit-csgo-compat';

const router = Router();

export function logSkinsAuthStatus(): void {
  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  const apiKey = process.env.API_KEY?.trim();
  if (!syncKey && (!apiKey || apiKey === 'default-key-change-me')) {
    console.warn(
      '[csgo-skins] Set CSGO_SKINS_SYNC_KEY or API_KEY in .env — requests will be rejected',
    );
    return;
  }
  if (syncKey) {
    console.log('[csgo-skins] auth: CSGO_SKINS_SYNC_KEY configured');
  } else {
    console.log('[csgo-skins] auth: API_KEY only (no CSGO_SKINS_SYNC_KEY)');
  }
}

type PlayerSyncBody = {
  steamId: string;
  weapons: SyncWeaponPayload[];
  clearKnifeSlot?: boolean;
  clearWeaponIds?: string[];
  clearGloveTeam?: "T" | "CT";
};

router.get('/ws-allowlist', async (_req: Request, res: Response) => {
  try {
    const { entries, count, source, sourcePath } = await loadWsWeaponsAllowlist(true);
    const keys = [...buildWsAllowlistSet(entries)];
    return res.json({
      ok: true,
      source,
      sourcePath,
      count,
      keys,
      entries,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'allowlist failed';
    return res.status(500).json({ error: message });
  }
});

router.post('/sync-weapons-cfg', async (_req: Request, res: Response) => {
  try {
    const result = await syncWeaponsCfgFromSite();
    if (!result.ok) {
      return res.status(500).json({ ok: false, error: result.error ?? 'sync failed' });
    }
    const weaponsReload = await reloadWeaponsPluginInGame();
    const rconReload = await reloadClutchSkinsInGame();
    return res.json({ ...result, weaponsReload, rconReload });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sync failed';
    return res.status(500).json({ error: message });
  }
});

router.post('/player-sync', async (req: Request, res: Response) => {
  const body = req.body as PlayerSyncBody;
  if (!body?.steamId || !Array.isArray(body.weapons)) {
    return res.status(400).json({ error: 'Expected { steamId, weapons[] }' });
  }

  try {
    const filtered = await filterCsgoCompatibleWeapons(body.weapons);
    const result = await syncPlayerLoadoutToWeaponsDb(body.steamId, filtered.weapons, {
      clearKnifeSlot: body.clearKnifeSlot,
      clearWeaponIds: body.clearWeaponIds,
      clearGloveTeam: body.clearGloveTeam,
    });
    const rconReload = await reloadClutchSkinsInGame();

    return res.json({
      ok: true,
      mode: 'db',
      steamId: result.steamId,
      steamIds: result.steamIds,
      weapons: filtered.weapons.length,
      skippedCs2: filtered.skipped.length,
      columns: result.columns,
      updated: result.updated,
      gloves: result.gloves,
      rconReload,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sync failed';
    console.error('[csgo-skins player-sync]', message);
    return res.status(500).json({ error: message });
  }
});

/**
 * Pull all equipped loadouts from site Postgres (site API) → local weapons SQLite.
 * No clutch_skins.txt. Optional cron / manual recovery.
 */
router.post('/sync-from-site', async (_req: Request, res: Response) => {
  try {
    const result = await syncAllLoadoutsFromSite();
    if (!result.ok && result.synced === 0) {
      return res.status(500).json(result);
    }
    return res.json({ mode: 'api', ...result, ok: result.errors.length === 0 || result.synced > 0 });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sync-from-site failed';
    console.error('[csgo-skins sync-from-site]', message);
    return res.status(500).json({ error: message });
  }
});

/** @deprecated Use POST /player-sync or POST /sync-from-site — writes a static file. */
router.post('/push', (_req: Request, res: Response) => {
  return res.status(410).json({
    error: 'Deprecated — use POST /api/csgo/skins/player-sync (per player) or POST /sync-from-site (bulk from Postgres via site API).',
    deprecated: true,
  });
});

export default router;
