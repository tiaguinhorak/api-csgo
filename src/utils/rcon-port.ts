import type { GameServer } from '../models/server';

/** CS:GO RCON listens on the game port when started with -usercon. */
export function resolveRconPort(server: Pick<GameServer, 'port' | 'rconPort'>): number {
  return server.port || server.rconPort;
}
