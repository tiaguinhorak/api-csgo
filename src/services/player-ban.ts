import { rconService } from './rcon';
import { resolveRconPort } from '../utils/rcon-port';
import { serverManager } from './server-manager';

function sanitizeBanReason(reason: string): string {
  return reason.replace(/["\n\r]/g, ' ').trim().slice(0, 120) || 'ban';
}

function normalizeSteamIdForSm(steamId: string): string | null {
  const trimmed = steamId.trim();
  const match = trimmed.match(/^STEAM_[0-5]:([0-1]):(\d+)$/i);
  if (match) {
    return `STEAM_1:${match[1]}:${match[2]}`;
  }
  if (/^\d{17}$/.test(trimmed)) {
    const base = BigInt('76561197960265728');
    const accountId = Number(BigInt(trimmed) - base);
    if (!Number.isFinite(accountId) || accountId < 0) return null;
    const y = accountId % 2;
    const z = Math.floor(accountId / 2);
    return `STEAM_1:${y}:${z}`;
  }
  return null;
}

export async function banPlayerOnAllServers(input: {
  steamId: string;
  minutes: number;
  reason: string;
}): Promise<{ ok: boolean; results: Array<{ serverId: string; ok: boolean; output?: string; error?: string }> }> {
  const steamId = normalizeSteamIdForSm(input.steamId);
  if (!steamId) {
    return { ok: false, results: [{ serverId: 'invalid', ok: false, error: 'Invalid steam id' }] };
  }

  const minutes = Math.max(0, Math.floor(input.minutes));
  const reason = sanitizeBanReason(input.reason);
  const command = `sm_addban ${steamId} ${minutes} ${reason}`;

  const servers = serverManager.listServers();
  if (servers.length === 0) {
    return { ok: false, results: [{ serverId: 'none', ok: false, error: 'No servers registered' }] };
  }

  const results: Array<{ serverId: string; ok: boolean; output?: string; error?: string }> = [];

  for (const server of servers) {
    try {
      const output = await rconService.sendCommand(
        server.host,
        resolveRconPort(server),
        server.rconPassword,
        command,
      );
      results.push({ serverId: server.id, ok: true, output });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      results.push({ serverId: server.id, ok: false, error: message });
    }
  }

  return { ok: results.some((r) => r.ok), results };
}

export async function unbanPlayerOnAllServers(steamIdRaw: string): Promise<{
  ok: boolean;
  results: Array<{ serverId: string; ok: boolean; output?: string; error?: string }>;
}> {
  const steamId = normalizeSteamIdForSm(steamIdRaw);
  if (!steamId) {
    return { ok: false, results: [{ serverId: 'invalid', ok: false, error: 'Invalid steam id' }] };
  }

  const command = `sm_unban ${steamId}`;
  const servers = serverManager.listServers();
  if (servers.length === 0) {
    return { ok: false, results: [{ serverId: 'none', ok: false, error: 'No servers registered' }] };
  }

  const results: Array<{ serverId: string; ok: boolean; output?: string; error?: string }> = [];

  for (const server of servers) {
    try {
      const output = await rconService.sendCommand(
        server.host,
        resolveRconPort(server),
        server.rconPassword,
        command,
      );
      results.push({ serverId: server.id, ok: true, output });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      results.push({ serverId: server.id, ok: false, error: message });
    }
  }

  return { ok: results.some((r) => r.ok), results };
}
