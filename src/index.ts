import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import matchesRouter from './routes/matches';
import serversRouter from './routes/servers';
import skinsRouter from './routes/skins';
import csgoSkinsPushRouter, { logSkinsAuthStatus } from './routes/csgo-skins-push';
import csgoStickersPushRouter from './routes/csgo-stickers-push';
import csgoAgentsPushRouter from './routes/csgo-agents-push';
import { skinManager } from './services/skin-manager';
import { resolveWeaponsDbPath } from './services/weapons-db-path';
import { logStickersDbPath } from './services/stickers-db-sync';
import { logAgentsDbPath } from './services/agents-db-sync';
import { startMatchLiveWatcher } from './services/match-live-watcher';
import { startSteamAllowlistSync } from './services/steam-allowlist-sync';
import { getMatchLiveDbPath } from './services/weapons-db-path';
import { siteBaseUrlFromEnv, siteRequestBaseUrl, siteSyncKeyFromEnv } from './services/site-http';
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
  const siteUrl = siteBaseUrlFromEnv();
  const siteRequestUrl = siteRequestBaseUrl();
  const syncKey = siteSyncKeyFromEnv();
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    matchPipeline: {
      siteUrl: siteUrl ?? null,
      siteRequestUrl: siteRequestUrl ?? null,
      syncKeyConfigured: Boolean(syncKey),
      matchLiveDb: (() => {
        try {
          return getMatchLiveDbPath();
        } catch {
          return null;
        }
      })(),
    },
    /** Present when player-sync writes the gloves SQLite table (commit a77152a+). */
    glovesPlayerSync: true,
    /** Present when sticker player-sync route is deployed. */
    stickersPlayerSync: true,
    /** Present when agent player-sync route is deployed. */
    agentsPlayerSync: true,
  });
});

app.use(requireApiAuth);

// Routes
app.use('/api/matches', matchesRouter);
app.use('/api/servers', serversRouter);
app.use('/api/skins', skinsRouter);
app.use('/api/csgo/skins', csgoSkinsPushRouter);
app.use('/api/csgo/stickers', csgoStickersPushRouter);
app.use('/api/csgo/agents', csgoAgentsPushRouter);

skinManager.initializeDefaultSkins();
logSkinsAuthStatus();
try {
  const dbPath = resolveWeaponsDbPath();
  console.log(`[csgo-skins] weapons DB resolved: ${dbPath}`);
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  console.warn(`[csgo-skins] weapons DB not ready: ${message}`);
}
logStickersDbPath();
logAgentsDbPath();

startMatchLiveWatcher();

if (process.env.CLUTCH_SITE_URL?.trim() && process.env.CSGO_SKINS_SYNC_KEY?.trim()) {
  startSteamAllowlistSync();
} else {
  console.warn(
    '[steam-allowlist] skipped — set CLUTCH_SITE_URL and CSGO_SKINS_SYNC_KEY to enable platform gate sync',
  );
}

const bindHost = process.env.BIND_HOST?.trim() || '0.0.0.0';

const server = app.listen(config.port, bindHost, () => {
  const sitePublic = siteBaseUrlFromEnv();
  const siteRequest = siteRequestBaseUrl();
  console.log(`CS:GO API running on http://${bindHost}:${config.port}`);
  console.log(
    `[boot] match pipeline site public=${sitePublic ?? '(unset)'} request=${siteRequest ?? '(unset)'} syncKey=${siteSyncKeyFromEnv() ? 'set' : 'MISSING'}`,
  );
});

server.on('error', (err: NodeJS.ErrnoException) => {
  if (err.code === 'EADDRINUSE') {
    console.error(
      `[api-csgo] Port ${config.port} already in use. Stop the other process or run: npm run pm2:recover`,
    );
    process.exit(1);
  }
  console.error('[api-csgo] Server error:', err);
  process.exit(1);
});

export default app;
