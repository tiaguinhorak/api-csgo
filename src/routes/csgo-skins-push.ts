import { Router, Request, Response } from 'express';
import express from 'express';
import fs from 'fs/promises';
import path from 'path';
import { config } from '../config';
import { reloadClutchSkinsInGame } from '../services/clutch-rcon';
import type { SyncWeaponPayload } from '../services/weapons-db-map';
import { syncPlayerLoadoutToWeaponsDb } from '../services/weapons-db-sync';
import {
  buildWsAllowlistSet,
  loadWsWeaponsAllowlist,
} from '../services/ws-weapons-config';

const router = Router();

export function logSkinsAuthStatus(): void {
  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  const apiKey = config.apiKey?.trim();
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
};

router.get('/ws-allowlist', (_req: Request, res: Response) => {
  const { entries, count } = loadWsWeaponsAllowlist(true);
  const keys = [...buildWsAllowlistSet(entries)];
  return res.json({
    ok: true,
    count,
    keys,
    entries,
  });
});

router.post('/player-sync', async (req: Request, res: Response) => {
  const body = req.body as PlayerSyncBody;
  if (!body?.steamId || !Array.isArray(body.weapons)) {
    return res.status(400).json({ error: 'Expected { steamId, weapons[] }' });
  }

  try {
    const result = await syncPlayerLoadoutToWeaponsDb(body.steamId, body.weapons, {
      clearKnifeSlot: body.clearKnifeSlot,
      clearWeaponIds: body.clearWeaponIds,
    });
    const rconReload = await reloadClutchSkinsInGame();

    return res.json({
      ok: true,
      mode: 'db',
      steamId: result.steamId,
      steamIds: result.steamIds,
      weapons: body.weapons.length,
      columns: result.columns,
      updated: result.updated,
      rconReload,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'sync failed';
    console.error('[csgo-skins player-sync]', message);
    return res.status(500).json({ error: message });
  }
});

/** Legacy: full KeyValues file export (deprecated — use POST /player-sync). */
router.post(
  '/push',
  express.text({ type: ['text/*', 'application/octet-stream'], limit: '2mb' }),
  async (req: Request, res: Response) => {
    const body = typeof req.body === 'string' ? req.body : '';
    if (!body.trim()) {
      return res.status(400).json({ error: 'Empty export body' });
    }

    const outPath =
      process.env.CLUTCH_SKINS_OUT?.trim() ||
      '/home/csgo/server/csgo/addons/sourcemod/data/clutch_skins.txt';

    try {
      await fs.mkdir(path.dirname(outPath), { recursive: true });
      const tmp = `${outPath}.tmp`;
      await fs.writeFile(tmp, body, 'utf8');
      await fs.rename(tmp, outPath);

      const rconReload = await reloadClutchSkinsInGame();

      return res.json({
        ok: true,
        mode: 'file',
        deprecated: true,
        bytes: Buffer.byteLength(body, 'utf8'),
        rconReload,
      });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Write failed';
      console.error('[csgo-skins-push] write failed:', message);
      return res.status(500).json({ error: message });
    }
  },
);

export default router;
