import { Router, Request, Response } from 'express';
import express from 'express';
import fs from 'fs/promises';
import path from 'path';
import { rconService } from '../services/rcon';

const router = Router();

const SYNC_HEADER = 'x-skins-sync-key';

function isAuthorized(req: Request): boolean {
  const expected = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  if (!expected) return false;
  const provided =
    (typeof req.headers[SYNC_HEADER] === 'string' ? req.headers[SYNC_HEADER] : null) ??
    (typeof req.headers['authorization'] === 'string'
      ? req.headers['authorization'].replace(/^Bearer\s+/i, '')
      : null);
  return provided === expected;
}

router.post(
  '/push',
  express.text({ type: ['text/*', 'application/octet-stream'], limit: '2mb' }),
  async (req: Request, res: Response) => {
    if (!isAuthorized(req)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

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

      const host = process.env.CSGO_SERVER_HOST?.trim() || '127.0.0.1';
      const rconPort = parseInt(
        process.env.CSGO_RCON_PORT || process.env.CSGO_SERVER_PORT || '27015',
        10,
      );
      const rconPassword = process.env.CSGO_RCON_PASSWORD?.trim() || '';

      let rconOk = false;
      if (rconPassword && Number.isFinite(rconPort)) {
        try {
          await rconService.sendCommand(host, rconPort, rconPassword, 'sm_reloadclutchskins');
          await rconService.sendCommand(host, rconPort, rconPassword, 'sm_clutch_applyskins');
          rconOk = true;
        } catch (rconErr: any) {
          console.warn('[csgo-skins-push] RCON reload failed:', rconErr?.message ?? rconErr);
        }
      }

      return res.json({
        ok: true,
        bytes: Buffer.byteLength(body, 'utf8'),
        path: outPath,
        rconReload: rconOk,
      });
    } catch (err: any) {
      console.error('[csgo-skins-push] write failed:', err);
      return res.status(500).json({ error: err?.message ?? 'Write failed' });
    }
  },
);

export default router;
