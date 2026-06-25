import { Router, Request, Response } from 'express';
import { syncAllStickersFromSite } from '../services/sync-stickers-from-site';
import { syncPlayerStickersToDb } from '../services/stickers-db-sync';
import { refreshPlayerStickersInGame } from '../services/clutch-rcon';
import type { StickerSyncEntry } from '../services/stickers-db-map';

const router = Router();

type PlayerSyncBody = {
  steamId: string;
  entries: StickerSyncEntry[];
};

router.post('/player-sync', async (req: Request, res: Response) => {
  const body = req.body as PlayerSyncBody;
  if (!body?.steamId || !Array.isArray(body.entries)) {
    return res.status(400).json({ error: 'Expected { steamId, entries[] }' });
  }

  try {
    const result = await syncPlayerStickersToDb(body.steamId, body.entries, {
      replacePlayerState: true,
    });
    const rconReload = await refreshPlayerStickersInGame(result.steamId);
    return res.json({
      ok: true,
      mode: 'db',
      steamId: result.steamId,
      steamIds: result.steamIds,
      entries: body.entries.length,
      updated: result.updated,
      dbPath: result.dbPath,
      clutchTable: result.clutchTable,
      legacyTable: result.legacyTable,
      clutchRows: result.clutchRows,
      legacyRows: result.legacyRows,
      rconReload,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sticker sync failed';
    console.error('[csgo-stickers player-sync]', message);
    return res.status(500).json({ error: message });
  }
});

router.post('/sync-from-site', async (_req: Request, res: Response) => {
  try {
    const result = await syncAllStickersFromSite();
    if (!result.ok && result.synced === 0) {
      return res.status(500).json(result);
    }
    return res.json({
      mode: 'api',
      ...result,
      ok: result.errors.length === 0 || result.synced > 0,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sync-from-site failed';
    console.error('[csgo-stickers sync-from-site]', message);
    return res.status(500).json({ error: message });
  }
});

export default router;
