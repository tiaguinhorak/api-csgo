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

async function resolveScreenSession(): Promise<string | null> {
  const configured = process.env.CLUTCH_CS_SCREEN?.trim();
  if (configured) {
    try {
      const { stdout } = await execFileAsync('screen', ['-ls'], { timeout: 5000 });
      const line = stdout
        .split('\n')
        .find((l) => l.includes(`.${configured}`));
      if (line) {
        return line.trim().split(/\s+/)[0] ?? null;
      }
    } catch {
      return null;
    }
  }

  try {
    const { stdout } = await execFileAsync('screen', ['-ls'], { timeout: 5000 });
    const line = stdout.split('\n').find((l) => /csgo-clutch/i.test(l));
    if (!line) return null;
    return line.trim().split(/\s+/)[0] ?? null;
  } catch {
    return null;
  }
}

async function sendViaScreen(sessionId: string, command: string): Promise<boolean> {
  await execFileAsync('screen', ['-S', sessionId, '-p', '0', '-X', 'stuff', `${command}^M`], {
    timeout: 5000,
  });
  return true;
}

async function reloadViaScreen(): Promise<boolean> {
  const session = await resolveScreenSession();
  if (!session) {
    return false;
  }

  try {
    await sendViaScreen(session, 'sm_reloadclutchskins');
    await new Promise((r) => setTimeout(r, 400));
    await sendViaScreen(session, 'sm_clutch_applyskins');
    console.log(`[clutch-rcon] applied via screen session ${session}`);
    return true;
  } catch (err) {
    console.warn('[clutch-rcon] screen fallback failed:', err);
    return false;
  }
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
      'sm_reloadclutchskins',
    );
    await rconService.sendCommand(
      target.host,
      target.port,
      target.password,
      'sm_clutch_applyskins',
    );
    return true;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(
      `[clutch-rcon] RCON failed (${target.host}:${target.port}): ${message} — trying screen`,
    );
    const viaScreen = await reloadViaScreen();
    if (!viaScreen) {
      console.warn(
        '[clutch-rcon] DB updated but in-game apply skipped (server offline/hibernating?). Skins apply on spawn.',
      );
    }
    return viaScreen;
  }
}
