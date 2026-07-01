const createRcon: (opts: { address: string; password: string }) => {
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  command(cmd: string): Promise<string>;
} = require('srcds-rcon');

const RCON_TIMEOUT_MS = 6_000;

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} excedeu ${ms / 1000}s`)), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

export class RconService {
  private connections: Map<string, ReturnType<typeof createRcon>> = new Map();

  private getKey(host: string, port: number): string {
    return `${host}:${port}`;
  }

  async connect(host: string, port: number, password: string): Promise<void> {
    const key = this.getKey(host, port);
    await this.disconnect(host, port);

    const rcon = createRcon({ address: `${host}:${port}`, password });
    await withTimeout(rcon.connect(), RCON_TIMEOUT_MS, 'RCON connect');
    this.connections.set(key, rcon);
  }

  async sendCommand(host: string, port: number, password: string, command: string): Promise<string> {
    const key = this.getKey(host, port);
    let rcon = this.connections.get(key);

    if (!rcon) {
      const client = createRcon({ address: `${host}:${port}`, password });
      await withTimeout(client.connect(), RCON_TIMEOUT_MS, 'RCON connect');
      this.connections.set(key, client);
      rcon = client;
    }

    try {
      return await withTimeout(rcon.command(command), RCON_TIMEOUT_MS, 'RCON command');
    } catch (error) {
      this.connections.delete(key);
      try {
        await rcon.disconnect();
      } catch {
        /* ignore */
      }
      throw error;
    }
  }

  async execConfig(host: string, port: number, password: string, configName: string): Promise<string> {
    return this.sendCommand(host, port, password, `exec ${configName}`);
  }

  async changeMap(host: string, port: number, password: string, map: string): Promise<string> {
    return this.sendCommand(host, port, password, `changelevel ${map}`);
  }

  async setMatchConfig(host: string, port: number, password: string, matchId: string): Promise<string> {
    const cmds = [
      `mp_match_restart_delay 15`,
      `sv_pausable 1`,
      `mp_autoteambalance 0`,
      `mp_limitteams 0`,
      `sv_allow_votes 0`,
      `mp_match_end_changelevel 0`,
      `sv_hibernate_when_empty 0`,
      `mp_team_timeout_max 1`,
      `mp_team_timeout_time 30`,
    ];
    const results = await Promise.all(
      cmds.map(cmd => this.sendCommand(host, port, password, cmd))
    );
    return results.join('\n');
  }

  async startMatch(host: string, port: number, password: string): Promise<string> {
    return this.sendCommand(host, port, password, 'mp_warmup_end');
  }

  /**
   * Apply gameplay rules (warmup duration/economy/buy, random spawns, DM respawn)
   * via engine cvars + the clutch_warmup_rules plugin cvars.
   */
  async applyGameRules(
    host: string,
    port: number,
    password: string,
    rules: {
      warmupSeconds: number;
      warmupStartMoney: number;
      warmupMaxMoney: number;
      warmupBuyAnywhere: boolean;
      randomSpawns: boolean;
      dmRespawn: boolean;
    },
  ): Promise<string> {
    const cmds = [
      `mp_warmuptime ${Math.max(0, rules.warmupSeconds)}`,
      `mp_warmuptime_all_players_connected ${Math.max(0, rules.warmupSeconds)}`,
      `mp_warmup_pausetimer 0`,
      // clutch_warmup_rules plugin owns warmup-only economy/buy + spawn behavior.
      `clutch_wr_enabled 1`,
      `clutch_wr_warmup_money ${Math.max(0, rules.warmupStartMoney)}`,
      `clutch_wr_warmup_maxmoney ${Math.max(0, rules.warmupMaxMoney)}`,
      `clutch_wr_buy_anywhere ${rules.warmupBuyAnywhere ? 1 : 0}`,
      `clutch_wr_random_spawns ${rules.randomSpawns ? 1 : 0}`,
      `clutch_wr_dm_respawn ${rules.dmRespawn ? 1 : 0}`,
    ];
    const results = await Promise.all(
      cmds.map((cmd) => this.sendCommand(host, port, password, cmd)),
    );
    return results.join('\n');
  }

  async pauseMatch(host: string, port: number, password: string): Promise<string> {
    return this.sendCommand(host, port, password, 'mp_pause_match');
  }

  async unpauseMatch(host: string, port: number, password: string): Promise<string> {
    return this.sendCommand(host, port, password, 'mp_unpause_match');
  }

  async clearMatchTracker(host: string, port: number, password: string): Promise<string> {
    return this.sendCommand(host, port, password, 'clutch_match_clear');
  }

  async beginMatchTracker(
    host: string,
    port: number,
    password: string,
    matchId: string,
    maxRounds: number,
  ): Promise<string> {
    return this.sendCommand(
      host,
      port,
      password,
      `clutch_match_begin ${matchId} ${maxRounds}`,
    );
  }

  async setMatchTrackerRoster(
    host: string,
    port: number,
    password: string,
    teamASteamPipe: string,
    teamBSteamPipe: string,
  ): Promise<string> {
    return this.sendCommand(
      host,
      port,
      password,
      `clutch_match_roster ${teamASteamPipe} ${teamBSteamPipe}`,
    );
  }

  async getStatus(host: string, port: number, password: string): Promise<string> {
    return this.sendCommand(host, port, password, 'status');
  }

  async disconnect(host: string, port: number): Promise<void> {
    const key = this.getKey(host, port);
    const rcon = this.connections.get(key);
    if (rcon) {
      try { await rcon.disconnect(); } catch {}
      this.connections.delete(key);
    }
  }

  disconnectAll(): void {
    for (const [, rcon] of this.connections) {
      try { rcon.disconnect(); } catch {}
    }
    this.connections.clear();
  }
}

export const rconService = new RconService();
