import type { GameServer } from '../models/server';

const SECRET_FIELDS = ['rconPassword', 'sshPassword', 'sshKey'] as const;

type SecretField = (typeof SECRET_FIELDS)[number];

export type PublicGameServer = Omit<GameServer, SecretField>;

export function sanitizeGameServer(server: GameServer): PublicGameServer {
  const copy = { ...server } as GameServer & Record<string, unknown>;
  for (const field of SECRET_FIELDS) {
    delete copy[field];
  }
  return copy as PublicGameServer;
}

export function sanitizeGameServers(servers: GameServer[]): PublicGameServer[] {
  return servers.map(sanitizeGameServer);
}
