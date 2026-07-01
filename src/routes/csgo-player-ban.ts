import { Router, type Request, type Response } from 'express';
import { banPlayerOnAllServers, unbanPlayerOnAllServers } from '../services/player-ban';

const router = Router();

router.post('/ban', async (req: Request, res: Response) => {
  const steamId = typeof req.body?.steamId === 'string' ? req.body.steamId.trim() : '';
  const minutes = Number(req.body?.minutes ?? 0);
  const reason = typeof req.body?.reason === 'string' ? req.body.reason : 'ban';

  if (!steamId) {
    return res.status(400).json({ error: 'steamId required' });
  }

  try {
    const result = await banPlayerOnAllServers({ steamId, minutes, reason });
    return res.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return res.status(500).json({ error: message });
  }
});

router.post('/unban', async (req: Request, res: Response) => {
  const steamId = typeof req.body?.steamId === 'string' ? req.body.steamId.trim() : '';
  if (!steamId) {
    return res.status(400).json({ error: 'steamId required' });
  }

  try {
    const result = await unbanPlayerOnAllServers(steamId);
    return res.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return res.status(500).json({ error: message });
  }
});

export default router;
