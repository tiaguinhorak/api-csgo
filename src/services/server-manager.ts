import { GameServer, CreateServerDTO } from '../models/server';
import { v4 as uuidv4 } from 'uuid';
import { sshService } from './ssh';
import { rconService } from './rcon';
import { config } from '../config';

class ServerManager {
  private servers: Map<string, GameServer> = new Map();

  registerServer(dto: CreateServerDTO): GameServer {
    const server: GameServer = {
      id: uuidv4(),
      name: dto.name,
      host: dto.host,
      sshPort: dto.sshPort || 22,
      sshUser: dto.sshUser,
      sshKey: dto.sshKey,
      sshPassword: dto.sshPassword,
      rconPort: dto.rconPort || 27015,
      rconPassword: dto.rconPassword,
      csgoDir: dto.csgoDir,
      screenSession: `csgo-${dto.name.toLowerCase().replace(/\s+/g, '-')}`,
      status: 'offline',
      port: dto.port || 27015,
      tickrate: dto.tickrate || config.csgo.defaultTickrate,
    };

    this.servers.set(server.id, server);
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
    return this.listServers('online').find(s => !s.currentMatchId);
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
      conn,
      server.csgoDir,
      server.screenSession,
      server.port,
      server.tickrate,
      config.csgo.defaultGameType,
      config.csgo.defaultGameMode,
      map,
      server.rconPassword,
      serverPassword
    );

    server.status = 'online';
    return server;
  }

  async stopServer(id: string): Promise<GameServer> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    const conn = this.getSshConnection(server);
    await sshService.stopServer(conn, server.screenSession);

    server.status = 'offline';
    server.currentMatchId = undefined;
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
          await rconService.getStatus(server.host, server.rconPort, server.rconPassword);
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

    return server;
  }

  async checkAllServers(): Promise<void> {
    for (const [id] of this.servers) {
      await this.checkStatus(id);
    }
  }

  async sendRconCommand(id: string, command: string): Promise<string> {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');

    return rconService.sendCommand(server.host, server.rconPort, server.rconPassword, command);
  }

  removeServer(id: string): void {
    this.servers.delete(id);
  }
}

export const serverManager = new ServerManager();
