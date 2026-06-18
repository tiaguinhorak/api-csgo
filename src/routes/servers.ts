import { Router, Request, Response } from 'express';
import { serverManager } from '../services/server-manager';

const router = Router();

router.get('/', (_req: Request, res: Response) => {
  const status = typeof _req.query.status === 'string' ? _req.query.status : undefined;
  const servers = status
    ? serverManager.listServers(status as any)
    : serverManager.listServers();
  res.json(servers);
});

router.get('/:id', (req: Request, res: Response) => {
  const server = serverManager.getServer(String(req.params.id));
  if (!server) return res.status(404).json({ error: 'Server not found' });
  res.json(server);
});

router.post('/', (req: Request, res: Response) => {
  try {
    const server = serverManager.registerServer(req.body);
    res.status(201).json(server);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/start', async (req: Request, res: Response) => {
  try {
    const { map, password } = req.body || {};
    const server = await serverManager.startServer(String(req.params.id), map, password);
    res.json(server);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/stop', async (req: Request, res: Response) => {
  try {
    const server = await serverManager.stopServer(String(req.params.id));
    res.json(server);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/restart', async (req: Request, res: Response) => {
  try {
    const { map } = req.body || {};
    const server = await serverManager.restartServer(String(req.params.id), map);
    res.json(server);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.get('/:id/status', async (req: Request, res: Response) => {
  try {
    const server = await serverManager.checkStatus(String(req.params.id));
    res.json(server);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/:id/rcon', async (req: Request, res: Response) => {
  try {
    const { command } = req.body;
    if (!command) return res.status(400).json({ error: 'Command is required' });
    const result = await serverManager.sendRconCommand(String(req.params.id), command);
    res.json({ result });
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.delete('/:id', (req: Request, res: Response) => {
  serverManager.removeServer(String(req.params.id));
  res.status(204).send();
});

export default router;
