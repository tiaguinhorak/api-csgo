import { execFile } from 'child_process';
import { promisify } from 'util';
import { rconService } from './rcon';

const execFileAsync = promisify(execFile);

function resolveRconTarget(): {
  host: string;
  port: number;
  password: string;
} | null {
  const password = process.env.CSGO_RCON_PASSWORD?.trim() || '';
  const port = parseInt(
    process.env.CSGO_RCON_PORT || process.env.CSGO_SERVER_PORT || '27015',
    10,
  );
  const host = process.env.CSGO_SERVER_HOST?.trim() || '127.0.0.1';

  if (!password || !Number.isFinite(port)) {
    return null;
  }

  return { host, port, password };
}

async function listScreenSessionIds(): Promise<string[]> {
  const ids: string[] = [];
  const configured = process.env.CLUTCH_CS_SCREEN?.trim();

  try {
    const { stdout } = await execFileAsync('screen', ['-ls'], { timeout: 8000 });
    for (const line of stdout.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('There')) continue;

      const id = trimmed.split(/\s+/)[0];
      if (!id) continue;

      if (configured && line.includes(`.${configured}`)) {
        ids.push(id);
      }
      if (/csgo-(clutch|warmup)/i.test(line)) {
        ids.push(id);
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn('[clutch-rcon] screen -ls failed:', message);
  }

  if (configured) {
    ids.push(configured);
  }

  return [...new Set(ids)];
}

async function sendViaScreen(sessionId: string, command: string): Promise<boolean> {
  const payload = `${command}^M`;
  try {
    await execFileAsync('screen', ['-S', sessionId, '-p', '0', '-X', 'stuff', payload], {
      timeout: 8000,
    });
    return true;
  } catch {
    try {
      await execFileAsync('screen', ['-S', sessionId, '-X', 'stuff', payload], {
        timeout: 8000,
      });
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[clutch-rcon] screen stuff failed (${sessionId}):`, message);
      return false;
    }
  }
}

async function reloadViaScreen(): Promise<boolean> {
  const sessions = await listScreenSessionIds();
  if (sessions.length === 0) {
    console.warn('[clutch-rcon] no screen session found (screen -ls / CLUTCH_CS_SCREEN)');
    return false;
  }

  for (const session of sessions) {
    if (await sendViaScreen(session, 'sm_clutch_applyskins')) {
      console.log(`[clutch-rcon] applied via screen session ${session}`);
      return true;
    }
  }

  return false;
}

async function sendRconOrScreen(command: string): Promise<boolean> {
  const target = resolveRconTarget();
  if (target) {
    try {
      await rconService.sendCommand(target.host, target.port, target.password, command);
      console.log(`[clutch-rcon] ${command} via RCON ${target.host}:${target.port}`);
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[clutch-rcon] RCON ${command} failed: ${message}`);
    }
  }

  const sessions = await listScreenSessionIds();
  for (const session of sessions) {
    if (await sendViaScreen(session, command)) {
      console.log(`[clutch-rcon] ${command} via screen ${session}`);
      return true;
    }
  }

  return false;
}

/** Reload kgns weapons.smx so new paintkits in weapons_english.cfg are recognized. */
export async function reloadWeaponsPluginInGame(): Promise<boolean> {
  const ok = await sendRconOrScreen('sm plugins reload weapons');
  if (!ok) {
    console.warn('[clutch-rcon] weapons plugin reload skipped (no RCON/screen)');
  }
  return ok;
}

export async function stageClutchLoadoutInGame(steamId?: string): Promise<boolean> {
  const trimmed = steamId?.trim();
  const command = trimmed
    ? `sm_clutch_loadout_pending "${trimmed}"`
    : 'sm_clutch_loadout_pending';
  const ok = await sendRconOrScreen(command);
  if (!ok) {
    console.warn('[clutch-rcon] loadout stage skipped (no RCON/screen)');
  }
  return ok;
}

export type WebLoadoutApplyMode = 'immediate' | 'staged' | 'deferred_join' | 'db_only';

export type WebLoadoutApplyResult = {
  commandSent: boolean;
  playerInGame: boolean;
};

function steam2Variants(steamId: string): string[] {
  const trimmed = steamId.trim();
  const variants = [trimmed];
  if (trimmed.startsWith('STEAM_0:')) {
    variants.push(`STEAM_1:${trimmed.slice(8)}`);
  } else if (trimmed.startsWith('STEAM_1:')) {
    variants.push(`STEAM_0:${trimmed.slice(8)}`);
  }
  return variants;
}

export async function isPlayerInGameServer(steamId: string): Promise<boolean> {
  const target = resolveRconTarget();
  if (!target) {
    return false;
  }

  try {
    const status = await rconService.sendCommand(
      target.host,
      target.port,
      target.password,
      'status',
    );
    for (const variant of steam2Variants(steamId)) {
      if (status.includes(variant)) {
        return true;
      }
    }
    return false;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn('[clutch-rcon] status check failed:', message);
    return false;
  }
}

async function getServerWarmupState(): Promise<'warmup' | 'live' | 'unknown'> {
  const target = resolveRconTarget();
  if (!target) {
    return 'unknown';
  }

  try {
    const out = await rconService.sendCommand(
      target.host,
      target.port,
      target.password,
      'mp_warmup_period',
    );
    if (/mp_warmup_period\s*=\s*1/i.test(out)) {
      return 'warmup';
    }
    if (/mp_warmup_period\s*=\s*0/i.test(out)) {
      return 'live';
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn('[clutch-rcon] mp_warmup_period check failed:', message);
  }

  return 'unknown';
}

export async function resolveWebLoadoutApplyMode(
  result: WebLoadoutApplyResult,
): Promise<WebLoadoutApplyMode> {
  if (!result.commandSent) {
    return 'db_only';
  }
  if (!result.playerInGame) {
    return 'deferred_join';
  }

  const warmup = await getServerWarmupState();
  if (warmup === 'warmup') {
    return 'immediate';
  }
  return 'staged';
}

/** Site equip / push-loadout — stage or apply via loadout_pending (no mid-match apply for players). */
export async function applyWebLoadoutInGame(steamId?: string): Promise<WebLoadoutApplyResult> {
  const trimmed = steamId?.trim();
  const playerInGame = trimmed ? await isPlayerInGameServer(trimmed) : false;
  const command = trimmed
    ? `sm_clutch_loadout_pending "${trimmed}"`
    : 'sm_clutch_loadout_pending';
  const commandSent = await sendRconOrScreen(command);
  if (!commandSent) {
    console.warn('[clutch-rcon] loadout stage skipped (no RCON/screen)');
  }
  return { commandSent, playerInGame };
}

export async function reloadClutchSkinsInGame(): Promise<boolean> {
  const target = resolveRconTarget();
  if (!target) {
    return reloadViaScreen();
  }

  try {
    await rconService.sendCommand(
      target.host,
      target.port,
      target.password,
      'sm_clutch_applyskins',
    );
    console.log(`[clutch-rcon] applied via RCON ${target.host}:${target.port}`);
    return true;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(
      `[clutch-rcon] RCON failed (${target.host}:${target.port}): ${message} — trying screen`,
    );
    const viaScreen = await reloadViaScreen();
    if (!viaScreen) {
      console.warn(
        '[clutch-rcon] DB updated but in-game apply skipped. Start CS + RCON, or run: ./scripts/reload-clutch-skins-ingame.sh',
      );
    }
    return viaScreen;
  }
}

/** Re-read agent rows from SQLite and apply player model (immediate, not staged). */
export async function refreshPlayerAgentsInGame(steamId?: string): Promise<boolean> {
  const trimmed = steamId?.trim();
  const command = trimmed
    ? `sm_clutch_refresh_agents "${trimmed}"`
    : 'sm_clutch_refresh_agents';
  const ok = await sendRconOrScreen(command);
  if (!ok) {
    console.warn('[clutch-rcon] agent refresh skipped (no RCON/screen)');
  }
  return ok;
}

/** Re-read sticker rows from SQLite and re-apply on held weapons (lighter than full applyskins). */
export async function refreshPlayerStickersInGame(steamId?: string): Promise<boolean> {
  const trimmed = steamId?.trim();
  const command = trimmed
    ? `sm_clutch_refresh_stickers "${trimmed}"`
    : 'sm_clutch_refresh_stickers';
  const ok = await sendRconOrScreen(command);
  if (!ok) {
    console.warn('[clutch-rcon] sticker refresh skipped (no RCON/screen)');
  }
  return ok;
}
