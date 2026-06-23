import { Router, Request, Response } from 'express';
import { syncPlayerStickersToDb } from '../services/stickers-db-sync';
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
    const result = await syncPlayerStickersToDb(body.steamId, body.entries);
    return res.json({
      ok: true,
      mode: 'db',
      steamId: result.steamId,
      steamIds: result.steamIds,
      entries: body.entries.length,
      updated: result.updated,
      dbPath: result.dbPath,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sticker sync failed';
    console.error('[csgo-stickers player-sync]', message);
    return res.status(500).json({ error: message });
  }
});

export default router;
