import { Router, Request, Response } from 'express';
import { matchManager } from '../services/match-manager';
import { serverManager } from '../services/server-manager';
import { rconService } from '../services/rcon';

const router = Router();

router.post('/', (req: Request, res: Response) => {
  try {
    const match = matchManager.createMatch(req.body);
    res.status(201).json(match);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.get('/', (req: Request, res: Response) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  const matches = status
    ? matchManager.listMatches(status as any)
    : matchManager.listMatches();
  res.json(matches);
});

router.get('/:id', (req: Request, res: Response) => {
  const match = matchManager.getMatch(String(req.params.id));
  if (!match) return res.status(404).json({ error: 'Match not found' });
  res.json(match);
});

router.post('/:id/start-veto', (req: Request, res: Response) => {
  try {
    const match = matchManager.startVeto(String(req.params.id));
    res.json(match);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/veto', (req: Request, res: Response) => {
  try {
    const { team, action, map } = req.body;
    if (!team || !action || !map) {
      return res.status(400).json({ error: 'team, action, and map are required' });
    }
    const match = matchManager.processVeto(String(req.params.id), team, action, map);
    res.json(match);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.get('/:id/veto-state', (req: Request, res: Response) => {
  try {
    const state = matchManager.getVetoState(String(req.params.id));
    res.json(state);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/start', async (req: Request, res: Response) => {
  try {
    const match = matchManager.getMatch(String(req.params.id));
    if (!match) return res.status(404).json({ error: 'Match not found' });

    const serverId = req.body.serverId || serverManager.getAvailableServer()?.id;
    if (!serverId) return res.status(400).json({ error: 'No available server' });

    const server = serverManager.getServer(serverId);
    if (!server) return res.status(404).json({ error: 'Server not found' });

    const updatedMatch = await matchManager.startMatch(String(req.params.id), server);
    server.currentMatchId = match.id;
    res.json(updatedMatch);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/pause', async (req: Request, res: Response) => {
  try {
    const match = matchManager.getMatch(String(req.params.id));
    if (!match) return res.status(404).json({ error: 'Match not found' });
    if (!match.serverId) return res.status(400).json({ error: 'Match has no server' });

    const server = serverManager.getServer(match.serverId);
    if (!server) return res.status(404).json({ error: 'Server not found' });

    await rconService.pauseMatch(server.host, server.rconPort, server.rconPassword);
    res.json({ success: true });
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/unpause', async (req: Request, res: Response) => {
  try {
    const match = matchManager.getMatch(String(req.params.id));
    if (!match) return res.status(404).json({ error: 'Match not found' });
    if (!match.serverId) return res.status(400).json({ error: 'Match has no server' });

    const server = serverManager.getServer(match.serverId);
    if (!server) return res.status(404).json({ error: 'Server not found' });

    await rconService.unpauseMatch(server.host, server.rconPort, server.rconPassword);
    res.json({ success: true });
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/end', async (req: Request, res: Response) => {
  try {
    const match = await matchManager.endMatch(String(req.params.id));
    res.json(match);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/cancel', (req: Request, res: Response) => {
  try {
    const match = matchManager.cancelMatch(String(req.params.id));
    res.json(match);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

export default router;
