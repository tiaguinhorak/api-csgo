import { Router, Request, Response } from 'express';
import { skinManager } from '../services/skin-manager';

const router = Router();

// --- Catalog ---

router.get('/catalog', (_req: Request, res: Response) => {
  const weaponId = typeof _req.query.weaponId === 'string' ? _req.query.weaponId : undefined;
  res.json(skinManager.listWeaponSkins(weaponId));
});

router.get('/catalog/:id', (req: Request, res: Response) => {
  const skin = skinManager.getWeaponSkin(String(req.params.id));
  if (!skin) return res.status(404).json({ error: 'Skin not found' });
  res.json(skin);
});

router.post('/catalog', (req: Request, res: Response) => {
  try {
    const skin = skinManager.registerWeaponSkin(req.body);
    res.status(201).json(skin);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

// --- Player Skins ---

router.get('/player/:steamId', (req: Request, res: Response) => {
  const skins = skinManager.getPlayerSkins(String(req.params.steamId));
  res.json(skins);
});

router.post('/player/:steamId/give', (req: Request, res: Response) => {
  try {
    const { skinId, wear, seed, stattrak, nametag } = req.body;
    const playerSkin = skinManager.giveSkin(
      String(req.params.steamId), skinId, wear, seed, stattrak, nametag
    );
    res.status(201).json(playerSkin);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.delete('/player/:steamId/:skinId', (req: Request, res: Response) => {
  const removed = skinManager.removePlayerSkin(String(req.params.skinId), String(req.params.steamId));
  if (!removed) return res.status(404).json({ error: 'Skin not found' });
  res.status(204).send();
});

// --- Loadout ---

router.get('/loadout/:steamId', (req: Request, res: Response) => {
  const fullData = req.query.full === 'true';
  if (fullData) {
    res.json(skinManager.getFullLoadoutData(String(req.params.steamId)));
  } else {
    res.json(skinManager.getLoadout(String(req.params.steamId)));
  }
});

router.post('/loadout/:steamId/equip', (req: Request, res: Response) => {
  try {
    const { playerSkinId } = req.body;
    const loadout = skinManager.equipSkin(String(req.params.steamId), playerSkinId);
    res.json(loadout);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/loadout/:steamId/unequip', (req: Request, res: Response) => {
  try {
    const { weaponId } = req.body;
    const loadout = skinManager.unequipSkin(String(req.params.steamId), weaponId);
    res.json(loadout);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

// --- Export for plugin ---

router.get('/export/:steamId', async (req: Request, res: Response) => {
  const data = await skinManager.exportLoadoutForPlugin(String(req.params.steamId));
  res.type('text/plain').send(data);
});

router.get('/export', async (_req: Request, res: Response) => {
  const data = await skinManager.exportAllForPlugin();
  res.type('text/plain').send(data);
});

export default router;
