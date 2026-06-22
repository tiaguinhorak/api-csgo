import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import matchesRouter from './routes/matches';
import serversRouter from './routes/servers';
import skinsRouter from './routes/skins';
import csgoSkinsPushRouter, { logSkinsAuthStatus } from './routes/csgo-skins-push';
import { skinManager } from './services/skin-manager';

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/matches', matchesRouter);
app.use('/api/servers', serversRouter);
app.use('/api/skins', skinsRouter);
app.use('/api/csgo/skins', csgoSkinsPushRouter);

skinManager.initializeDefaultSkins();
logSkinsAuthStatus();

app.listen(config.port, () => {
  console.log(`CS:GO API running on port ${config.port}`);
});

export default app;
