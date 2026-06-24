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
    ? `sm_clutch_loadout_pending ${trimmed}`
    : 'sm_clutch_loadout_pending';
  const ok = await sendRconOrScreen(command);
  if (!ok) {
    console.warn('[clutch-rcon] loadout stage skipped (no RCON/screen)');
  }
  return ok;
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
