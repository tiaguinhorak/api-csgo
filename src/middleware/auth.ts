import type { Request, Response, NextFunction } from 'express';
import { config } from '../config';

const SYNC_HEADER = 'x-skins-sync-key';
const API_KEY_HEADER = 'x-api-key';

export function getProvidedAuthKey(req: Request): string | null {
  const sync = req.get(SYNC_HEADER);
  if (sync) return sync;
  const api = req.get(API_KEY_HEADER);
  if (api) return api;
  const auth = req.get('authorization');
  if (auth) return auth.replace(/^Bearer\s+/i, '');
  return null;
}

export function isAuthorizedRequest(req: Request): boolean {
  const provided = getProvidedAuthKey(req);
  if (!provided) return false;

  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim();
  if (syncKey && provided === syncKey) return true;

  const apiKey = config.apiKey?.trim();
  if (apiKey && apiKey !== 'default-key-change-me' && provided === apiKey) {
    return true;
  }

  return false;
}

export function requireApiAuth(req: Request, res: Response, next: NextFunction): void {
  if (req.path === '/health') {
    next();
    return;
  }
  if (!isAuthorizedRequest(req)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  next();
}

export function assertProductionApiKey(): void {
  if (process.env.NODE_ENV !== 'production') {
    return;
  }

  const apiKey = config.apiKey?.trim();
  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim();

  if (syncKey) {
    return;
  }

  if (apiKey && apiKey !== 'default-key-change-me') {
    return;
  }

  console.error(
    '[api-csgo] Set API_KEY, CSGO_API_KEY, or CSGO_SKINS_SYNC_KEY in production.',
  );
  process.exit(1);
}
