import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import matchesRouter from './routes/matches';
import serversRouter from './routes/servers';
import skinsRouter from './routes/skins';
import csgoSkinsPushRouter, { logSkinsAuthStatus } from './routes/csgo-skins-push';
import { skinManager } from './services/skin-manager';
import { resolveWeaponsDbPath } from './services/weapons-db-path';
import { assertProductionApiKey, requireApiAuth } from './middleware/auth';

const app = express();

assertProductionApiKey();

const siteOrigin = process.env.SITE_ORIGIN?.trim();

app.use(helmet());
app.use(
  cors(
    siteOrigin
      ? { origin: siteOrigin, methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'] }
      : { origin: false },
  ),
);
app.use(express.json({ limit: '64kb' }));

// Health check (no auth — bind to private network in production)
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use(requireApiAuth);

// Routes
app.use('/api/matches', matchesRouter);
app.use('/api/servers', serversRouter);
app.use('/api/skins', skinsRouter);
app.use('/api/csgo/skins', csgoSkinsPushRouter);

skinManager.initializeDefaultSkins();
logSkinsAuthStatus();
try {
  const dbPath = resolveWeaponsDbPath();
  console.log(`[csgo-skins] weapons DB resolved: ${dbPath}`);
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  console.warn(`[csgo-skins] weapons DB not ready: ${message}`);
}

app.listen(config.port, () => {
  console.log(`CS:GO API running on port ${config.port}`);
});

export default app;
