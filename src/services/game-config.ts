import { siteRequestBaseUrl, siteSyncKeyFromEnv } from './site-http';

export interface ServerGameConfig {
  pool: string;
  enabled: boolean;
  warmupSeconds: number;
  warmupStartMoney: number;
  warmupMaxMoney: number;
  warmupBuyAnywhere: boolean;
  randomSpawns: boolean;
  dmRespawn: boolean;
  gameType: number;
  gameMode: number;
}

function envInt(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function envBool(name: string, fallback: boolean): boolean {
  const raw = process.env[name]?.trim().toLowerCase();
  if (raw === undefined || raw === '') return fallback;
  return raw === '1' || raw === 'true' || raw === 'yes';
}

/** Env-based fallback so gameplay rules apply even without the site. */
export function defaultGameConfig(pool: string): ServerGameConfig {
  const dm = pool === 'warmup';
  return {
    pool,
    enabled: envBool('CLUTCH_GAME_RULES_ENABLED', true),
    warmupSeconds: envInt('CLUTCH_WARMUP_SECONDS', 60),
    warmupStartMoney: envInt('CLUTCH_WARMUP_MONEY', 16000),
    warmupMaxMoney: envInt('CLUTCH_WARMUP_MAX_MONEY', 16000),
    warmupBuyAnywhere: envBool('CLUTCH_WARMUP_BUY_ANYWHERE', true),
    randomSpawns: envBool('CLUTCH_RANDOM_SPAWNS', true),
    dmRespawn: envBool('CLUTCH_DM_RESPAWN', dm),
    gameType: envInt('CSGO_GAME_TYPE', 0),
    gameMode: envInt('CSGO_GAME_MODE', 1),
  };
}

/** Fetch a pool's gameplay config from the site, falling back to env defaults. */
export async function fetchGameConfig(pool: string): Promise<ServerGameConfig> {
  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();
  if (!base || !key) {
    return defaultGameConfig(pool);
  }

  try {
    const url = `${base}/api/csgo/game-config?pool=${encodeURIComponent(pool)}`;
    const res = await fetch(url, {
      headers: { 'x-skins-sync-key': key },
      signal: AbortSignal.timeout(6_000),
    });
    if (!res.ok) {
      return defaultGameConfig(pool);
    }
    const data = (await res.json()) as { config?: Partial<ServerGameConfig> };
    const fallback = defaultGameConfig(pool);
    return { ...fallback, ...(data.config ?? {}), pool };
  } catch {
    return defaultGameConfig(pool);
  }
}
