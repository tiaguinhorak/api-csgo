import { Router, Request, Response } from 'express';
import { syncPlayerAgentsToDb } from '../services/agents-db-sync';
import {
  isPlayerInGameServer,
  refreshPlayerAgentsInGame,
} from '../services/clutch-rcon';
import type { AgentSyncEntry } from '../services/agents-db-map';

const router = Router();

type PlayerSyncBody = {
  steamId: string;
  entries: AgentSyncEntry[];
};

router.post('/player-sync', async (req: Request, res: Response) => {
  const body = req.body as PlayerSyncBody;
  if (!body?.steamId || !Array.isArray(body.entries)) {
    return res.status(400).json({ error: 'Expected { steamId, entries[] }' });
  }

  try {
    const result = await syncPlayerAgentsToDb(body.steamId, body.entries);
    const playerInGame = await isPlayerInGameServer(result.steamId);
    const commandSent = await refreshPlayerAgentsInGame(result.steamId);
    return res.json({
      ok: true,
      mode: 'db',
      applyMode: 'immediate',
      playerInGame,
      steamId: result.steamId,
      steamIds: result.steamIds,
      entries: body.entries.length,
      updated: result.updated,
      dbPath: result.dbPath,
      table: result.table,
      rows: result.rows,
      rconReload: commandSent,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'agent sync failed';
    console.error('[csgo-agents player-sync]', message);
    return res.status(500).json({ error: message });
  }
});

export default router;
