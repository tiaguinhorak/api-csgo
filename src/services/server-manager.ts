import { GameServer, CreateServerDTO } from '../models/server';
import { v4 as uuidv4 } from 'uuid';
import { sshService } from './ssh';
import { rconService } from './rcon';
import { config } from '../config';
import { stateStore } from './state-store';
import { resolveRconPort } from '../utils/rcon-port';
import { resolveRconConnectHost, resolveSshConnectionHost } from '../utils/server-connection';

class ServerManager {
  private servers = stateStore.servers;

  registerServer(dto: CreateServerDTO): GameServer {
    const host = dto.host?.trim();
    if (!host) throw new Error('Host é obrigatório.');

    // O site consulta os servidores via A2S no host público; loopback/LAN não são alcançáveis de fora.
    // Para api-csgo + srcds na mesma VPS, registre o IP PÚBLICO — o mapeamento p/ loopback é interno.
    const allowLocal = process.env.CSGO_ALLOW_LOCAL_REGISTER === '1';
    if (!allowLocal && this.isUnreachableHost(host)) {
      throw new Error(
        `Host "${host}" é loopback/LAN e o painel não consegue consultá-lo de fora. ` +
          `Use o IP público da VPS (ex.: o mesmo de CSGO_PUBLIC_HOST).`,
      );
    }

    const port = dto.port ?? 27015;
    const duplicate = Array.from(this.servers.values()).find(
      (s) => s.host === host && s.port === port,
    );
    if (duplicate) {
      throw new Error(
        `Já existe um servidor registrado em ${host}:${port} (${duplicate.name}). ` +
          `Edite ou remova o existente antes de criar outro.`,
      );
    }

    const envScreen = process.env.CLUTCH_CS_SCREEN?.trim();
    const screenSession = this.sanitizeScreenSession(
      dto.screenSession?.trim() ||
        envScreen ||
        `csgo-${dto.name.toLowerCase().replace(/\s+/g, '-')}-${port}`,
    );

    const server: GameServer = {
      id: uuidv4(),
      name: dto.name,
      host,
      sshPort: dto.sshPort || 22,
      sshUser: dto.sshUser,
      sshKey: dto.sshKey,
      sshPassword: dto.sshPassword,
      rconPort: dto.rconPort ?? port,
      rconPassword: dto.rconPassword,
      csgoDir: dto.csgoDir,
      screenSession,
      status: 'offline',
      port,
      tickrate: dto.tickrate || config.csgo.defaultTickrate,
      pool: dto.pool ?? 'public',
    };

    this.servers.set(server.id, server);
    stateStore.persist();
    return server;
  }

  private isUnreachableHost(host: string): boolean {
    if (host === '127.0.0.1' || host === 'localhost' || host === '::1') return true;
    if (/^10\./.test(host)) return true;
    if (/^192\.168\./.test(host)) return true;
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(host)) return true;
    return false;
  }

  private sanitizeScreenSession(raw: string): string {
    const clean = raw.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
    return clean || `csgo-${Date.now()}`;
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
      host: resolveSshConnectionHost(server),
      port: server.sshPort,
      username: server.sshUser,
      privateKey: server.sshKey,
      password: server.sshPassword,
    };
  }

  private getRconHost(server: GameServer): string {
    return resolveRconConnectHost(server);
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

    // Dá um tempo para o screen subir e detecta crash imediato (porta ocupada, GSLT, binário ausente).
    await new Promise(r => setTimeout(r, 4000));
    const running = await sshService.serverStatus(conn, server.screenSession);
    if (running !== 'running') {
      const log = await sshService.readServerLog(conn, server.csgoDir);
      server.status = 'offline';
      stateStore.persist();
      const hint = log
        ? `O srcds não permaneceu no ar. Últimas linhas do log:\n${log}`
        : 'O srcds não permaneceu no ar (screen encerrou). Verifique se o CS:GO está instalado em ' +
          `${server.csgoDir} e se a porta ${server.port} está livre.`;
      throw new Error(hint);
    }

    // Aguarda até 30s pelo RCON responder
    for (let i = 0; i < 30; i++) {
      await new Promise(r => setTimeout(r, 1000));
      try {
        await rconService.getStatus(
          this.getRconHost(server),
          resolveRconPort(server),
          server.rconPassword,
        );
        server.status = 'online';
        stateStore.persist();
        return server;
      } catch {}
    }

    // Screen está rodando mas RCON não respondeu: provável senha RCON errada ou ainda carregando.
    const log = await sshService.readServerLog(conn, server.csgoDir);
    server.status = 'offline';
    stateStore.persist();
    throw new Error(
      'Servidor iniciou mas o RCON não respondeu em 30s. ' +
        'Confira CSGO_RCON_PASSWORD e -usercon.' +
        (log ? `\nLog:\n${log}` : ''),
    );
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
          await rconService.getStatus(
            this.getRconHost(server),
            resolveRconPort(server),
            server.rconPassword,
          );
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

    return rconService.sendCommand(
      this.getRconHost(server),
      resolveRconPort(server),
      server.rconPassword,
      command,
    );
  }

  removeServer(id: string): void {
    this.servers.delete(id);
    stateStore.persist();
  }

  updateServer(
    id: string,
    patch: { name?: string; pool?: GameServer['pool']; screenSession?: string },
  ): GameServer {
    const server = this.servers.get(id);
    if (!server) throw new Error('Server not found');
    if (patch.name !== undefined) {
      const trimmed = patch.name.trim();
      if (!trimmed) throw new Error('Name is required');
      server.name = trimmed;
    }
    if (patch.pool !== undefined) {
      server.pool = patch.pool;
    }
    if (patch.screenSession !== undefined) {
      const trimmed = patch.screenSession.trim();
      if (!trimmed) throw new Error('screenSession is required');
      server.screenSession = trimmed;
    }
    stateStore.persist();
    return server;
  }
}

export const serverManager = new ServerManager();
