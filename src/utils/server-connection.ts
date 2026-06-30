import type { GameServer } from '../models/server';

function isLoopbackHost(host: string): boolean {
  return host === '127.0.0.1' || host === 'localhost' || host === '::1';
}

function localManagementHosts(): string[] {
  const hosts = new Set<string>();
  const publicHost = process.env.CSGO_PUBLIC_HOST?.trim();
  const serverHost = process.env.CSGO_SERVER_HOST?.trim();
  const extra = process.env.CSGO_LOCAL_HOSTS?.trim();

  if (publicHost) hosts.add(publicHost);
  if (serverHost) hosts.add(serverHost);
  if (extra) {
    for (const part of extra.split(',')) {
      const trimmed = part.trim();
      if (trimmed) hosts.add(trimmed);
    }
  }

  hosts.add('127.0.0.1');
  hosts.add('localhost');
  return [...hosts];
}

/** Por padrão api-csgo e srcds ficam na mesma VPS; registre IP público mas gerencie via loopback. */
function sameMachineManagement(): boolean {
  return process.env.CSGO_SAME_MACHINE?.trim() !== '0';
}

/** api-csgo and srcds on the same machine — RCON/screen via loopback even when registry uses public IP. */
export function isLocalGameServer(server: Pick<GameServer, 'host'>): boolean {
  if (sameMachineManagement()) return true;
  if (isLoopbackHost(server.host)) return true;
  return localManagementHosts().includes(server.host);
}

export function resolveRconConnectHost(server: Pick<GameServer, 'host'>): string {
  // Se o gerenciamento (screen/SSH) é local, RCON também deve ser loopback.
  const sshHost = resolveSshConnectionHost(server);
  if (isLoopbackHost(sshHost)) {
    return '127.0.0.1';
  }
  if (isLocalGameServer(server)) {
    const loopback = process.env.CSGO_SERVER_HOST?.trim();
    if (loopback && isLoopbackHost(loopback)) return loopback;
    return '127.0.0.1';
  }
  return server.host;
}

export function resolveSshConnectionHost(server: Pick<GameServer, 'host'>): string {
  if (isLocalGameServer(server)) {
    return '127.0.0.1';
  }
  return server.host;
}
