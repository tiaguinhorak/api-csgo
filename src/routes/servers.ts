import { Router, Request, Response } from 'express';
import { serverManager } from '../services/server-manager';
import { sanitizeGameServer, sanitizeGameServers } from '../middleware/sanitize-server';

const router = Router();

router.get('/', (_req: Request, res: Response) => {
  const status = typeof _req.query.status === 'string' ? _req.query.status : undefined;
  const servers = status
    ? serverManager.listServers(status as 'online' | 'offline' | 'busy')
    : serverManager.listServers();
  res.json(sanitizeGameServers(servers));
});

router.get('/:id', (req: Request, res: Response) => {
  const server = serverManager.getServer(String(req.params.id));
  if (!server) return res.status(404).json({ error: 'Server not found' });
  res.json(sanitizeGameServer(server));
});

router.post('/', (req: Request, res: Response) => {
  try {
    const server = serverManager.registerServer(req.body);
    res.status(201).json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.post('/:id/start', async (req: Request, res: Response) => {
  try {
    const { map, password } = req.body || {};
    const server = await serverManager.startServer(String(req.params.id), map, password);
    res.json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.post('/:id/stop', async (req: Request, res: Response) => {
  try {
    const server = await serverManager.stopServer(String(req.params.id));
    res.json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.post('/:id/restart', async (req: Request, res: Response) => {
  try {
    const { map } = req.body || {};
    const server = await serverManager.restartServer(String(req.params.id), map);
    res.json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.get('/:id/status', async (req: Request, res: Response) => {
  try {
    const server = await serverManager.checkStatus(String(req.params.id));
    res.json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.post('/:id/rcon', async (req: Request, res: Response) => {
  try {
    const { command } = req.body;
    if (!command) return res.status(400).json({ error: 'Command is required' });
    const result = await serverManager.sendRconCommand(String(req.params.id), command);
    res.json({ result });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.patch('/:id', (req: Request, res: Response) => {
  try {
    const { name, pool } = req.body || {};
    const patch: { name?: string; pool?: 'ranked' | 'warmup' | 'public' } = {};
    if (typeof name === 'string') patch.name = name;
    if (pool === 'ranked' || pool === 'warmup' || pool === 'public') patch.pool = pool;
    if (Object.keys(patch).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    const server = serverManager.updateServer(String(req.params.id), patch);
    res.json(sanitizeGameServer(server));
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Bad request';
    res.status(400).json({ error: message });
  }
});

router.delete('/:id', (req: Request, res: Response) => {
  serverManager.removeServer(String(req.params.id));
  res.status(204).send();
});

export default router;
