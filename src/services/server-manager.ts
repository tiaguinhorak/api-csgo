import { GameServer, CreateServerDTO } from '../models/server';
import { v4 as uuidv4 } from 'uuid';
import { sshService } from './ssh';
import { rconService } from './rcon';
import { config } from '../config';
import { stateStore } from './state-store';
import { resolveRconPort } from '../utils/rcon-port';

class ServerManager {
  private servers = stateStore.servers;

  registerServer(dto: CreateServerDTO): GameServer {
    const server: GameServer = {
      id: uuidv4(),
      name: dto.name,
      host: dto.host,
      sshPort: dto.sshPort || 22,
      sshUser: dto.sshUser,
      sshKey: dto.sshKey,
      sshPassword: dto.sshPassword,
      rconPort: dto.rconPort ?? dto.port ?? 27015,
      rconPassword: dto.rconPassword,
      csgoDir: dto.csgoDir,
      screenSession: `csgo-${dto.name.toLowerCase().replace(/\s+/g, '-')}`,
      status: 'offline',
      port: dto.port ?? 27015,
      tickrate: dto.tickrate || config.csgo.defaultTickrate,
      pool: dto.pool ?? 'public',
    };

    this.servers.set(server.id, server);
    stateStore.persist();
    return server;
  }

  getServer(id: string): GameServer | undefined {
    return this.servers.get(id);
  }

  listServers(status?: GameServer['status']): GameServer[] {
    const all = Array.from(this.servers.values());
    if (status) return all.filter(s => s.status === status);
    return all;
  }

  getAvailableServer(): GameServer | undefined {
    return this.listServers('online').find((s) => !s.currentMatchId);
  }

  /**
   * Reserva um servidor livre para a partida (evita duas partidas no mesmo host).
   * Retorna null se todos estão ocupados ou o preferredId está inválido/ocupado.
   */
  reserveServerForMatch(matchId: string, preferredServerId?: string): GameServer | null {
    const tryReserve = (server: GameServer | undefined): GameServer | null => {
      if (!server) return null;
      const pool = server.pool ?? 'ranked';
      if (pool !== 'ranked') return null;
      if (server.currentMatchId) return null;
      if (server.status !== 'online') return null;
      server.currentMatchId = matchId;
      server.status = 'busy';
      stateStore.persist();
      return server;
    };

    if (preferredServerId) {
      return tryReserve(this.servers.get(preferredServerId));
    }

    for (const server of this.listServers('online')) {
      const pool = server.pool ?? 'ranked';
      if (pool !== 'ranked') continue;
      if (!server.currentMatchId) {
        const reserved = tryReserve(server);
        if (reserved) return reserved;
      }
    }

    return null;
  }

  private getSshConnection(server: GameServer) {
    return {
      host: server.host,
      port: server.sshPort,
      username: server.sshUser,
      privateKey: server.sshKey,
      password: server.sshPassword,
    };
  }

  async startServer(id: string, map: string = 'de_dust2', serverPassword?: string): Promise<GameServer> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    const conn = this.getSshConnection(server);
    await sshService.startServer(
      conn, server.csgoDir, server.screenSession,
      server.port, server.tickrate,
      config.csgo.defaultGameType, config.csgo.defaultGameMode,
      map, server.rconPassword, serverPassword
    );

    // Aguarda até 30s pelo RCON responder
    for (let i = 0; i < 30; i++) {
      await new Promise(r => setTimeout(r, 1000));
      try {
        await rconService.getStatus(server.host, resolveRconPort(server), server.rconPassword);
        server.status = 'online';
        stateStore.persist();
        return server;
      } catch {}
    }

    server.status = 'offline';
    stateStore.persist();
    return server;
  }

  async stopServer(id: string): Promise<GameServer> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    const conn = this.getSshConnection(server);
    await sshService.stopServer(conn, server.screenSession);

    server.status = 'offline';
    server.currentMatchId = undefined;
    stateStore.persist();
    return server;
  }

  async restartServer(id: string, map?: string): Promise<GameServer> {
    await this.stopServer(id);
    await this.startServer(id, map);
    return this.servers.get(id)!;
  }

  async checkStatus(id: string): Promise<GameServer> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    try {
      const conn = this.getSshConnection(server);
      const running = await sshService.serverStatus(conn, server.screenSession);

      if (running === 'running') {
        // Test RCON connection
        try {
          await rconService.getStatus(server.host, resolveRconPort(server), server.rconPassword);
          server.status = server.currentMatchId ? 'busy' : 'online';
        } catch {
          server.status = 'offline';
        }
      } else {
        server.status = 'offline';
      }
    } catch {
      server.status = 'offline';
    }

    stateStore.persist();
    return server;
  }

  releaseServer(serverId: string): void {
    const server = this.servers.get(serverId);
    if (!server) return;
    server.currentMatchId = undefined;
    if (server.status === 'busy') {
      server.status = 'online';
    }
    stateStore.persist();
  }

  assignMatch(serverId: string, matchId: string): void {
    const server = this.servers.get(serverId);
    if (!server) return;
    server.currentMatchId = matchId;
    if (server.status === 'online') {
      server.status = 'busy';
    }
    stateStore.persist();
  }

  async checkAllServers(): Promise<void> {
    for (const [id] of this.servers) {
      await this.checkStatus(id);
    }
  }

  async sendRconCommand(id: string, command: string): Promise<string> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    return rconService.sendCommand(server.host, resolveRconPort(server), server.rconPassword, command);
  }

  removeServer(id: string): void {
    this.servers.delete(id);
    stateStore.persist();
  }
}

export const serverManager = new ServerManager();
