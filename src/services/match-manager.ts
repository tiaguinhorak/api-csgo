import { Match, CreateMatchDTO, MatchStatus, VetoAction } from '../models/match';
import { getAvailableMaps, generateVetoSteps, VetoStep, VetoStepDef } from '../models/veto';
import { GameServer } from '../models/server';
import { config } from '../config';
import { v4 as uuidv4 } from 'uuid';
import { rconService } from './rcon';
import { serverManager } from './server-manager';
import { stateStore } from './state-store';
import { resolveRconPort } from '../utils/rcon-port';

class MatchManager {
  private matches = stateStore.matches;
  private stepsCache: Map<string, VetoStepDef[]> = new Map();

  private getSteps(match: Match): VetoStepDef[] {
    const key = match.id;
    let steps = this.stepsCache.get(key);
    if (!steps) {
      steps = generateVetoSteps(match.mapPool);
      this.stepsCache.set(key, steps);
    }
    return steps;
  }

  createMatch(dto: CreateMatchDTO): Match {
    const match: Match = {
      id: uuidv4(),
      roomId: dto.roomId,
      teamA: dto.teamA,
      teamB: dto.teamB,
      mapPool: dto.mapPool.length > 0 ? dto.mapPool : config.veto.mapPool,
      vetoHistory: [],
      status: 'waiting_players',
      createdAt: new Date().toISOString(),
      config: {
        gameType: config.csgo.defaultGameType,
        gameMode: config.csgo.defaultGameMode,
        tickrate: config.csgo.defaultTickrate,
        tvDelay: config.csgo.tvDelay,
        enablePause: true,
        enableCoach: false,
        maxRounds: config.csgo.maxRounds,
        overtimeRounds: config.csgo.overtimeRounds,
        ...dto.config,
      },
    };

    this.matches.set(match.id, match);
    stateStore.persist();
    return match;
  }

  getMatch(id: string): Match | undefined {
    return this.matches.get(id);
  }

  listMatches(status?: MatchStatus): Match[] {
    const all = Array.from(this.matches.values());
    if (status) return all.filter(m => m.status === status);
    return all;
  }

  startVeto(matchId: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status === 'veto' || match.status === 'ready' || match.status === 'live') {
      return match;
    }
    if (match.status !== 'waiting_players') throw new Error('Invalid match status');

    match.status = 'veto';
    this.processAutoStep(match);
    stateStore.persist();
    return match;
  }

  private processAutoStep(match: Match): void {
    const steps = this.getSteps(match);
    const idx = match.vetoHistory.length;
    if (idx >= steps.length) {
      match.status = 'ready';
      return;
    }

    const step = steps[idx];
    if (step.action !== 'random') return;

    const used = match.vetoHistory.map(v => v.map);
    const available = getAvailableMaps(match.mapPool, used);
    if (available.length === 0) { match.status = 'ready'; return; }

    const map = available[Math.floor(Math.random() * available.length)];
    match.vetoHistory.push({ team: step.team, action: 'random', map, timestamp: new Date().toISOString() });
    match.selectedMap = map;
    match.status = 'ready';
  }

  processVeto(matchId: string, team: 'A' | 'B', action: 'ban' | 'pick', map: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status !== 'veto') throw new Error('Veto is not active');

    const steps = this.getSteps(match);
    const idx = match.vetoHistory.length;
    if (idx >= steps.length) {
      match.status = 'ready';
      throw new Error('Veto already completed');
    }

    const step = steps[idx];
    if (step.team !== team) throw new Error(`It's ${step.team}'s turn`);
    if (step.action !== action) throw new Error(`Expected action: ${step.action}`);

    const used = match.vetoHistory.map(v => v.map);
    const available = getAvailableMaps(match.mapPool, used);
    if (!available.includes(map)) throw new Error(`Map ${map} is not available (available: ${available.join(', ')})`);

    match.vetoHistory.push({ team, action, map, timestamp: new Date().toISOString() });
    if (action === 'pick') match.selectedMap = map;

    this.processAutoStep(match);
    stateStore.persist();
    return match;
  }

  getVetoState(matchId: string): {
    history: VetoAction[];
    currentStep: VetoStep | null;
    availableMaps: string[];
    isComplete: boolean;
  } {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');

    const steps = this.getSteps(match);
    const idx = match.vetoHistory.length;
    const isComplete = idx >= steps.length || match.status === 'ready';
    const used = match.vetoHistory.map(v => v.map);
    const availableMaps = getAvailableMaps(match.mapPool, used);

    let currentStep: VetoStep | null = null;
    if (!isComplete && match.status === 'veto') {
      const s = steps[idx];
      currentStep = { ...s, availableMaps };
    }

    return { history: match.vetoHistory, currentStep, availableMaps, isComplete };
  }

  async startMatch(matchId: string, server: GameServer): Promise<Match> {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status !== 'ready') throw new Error('Match is not ready');
    if (!match.selectedMap) throw new Error('No map selected');

    match.serverId = server.id;
    match.status = 'live';

    const rconPort = resolveRconPort(server);

    await rconService.setMatchConfig(server.host, rconPort, server.rconPassword, matchId);
    await rconService.sendCommand(server.host, rconPort, server.rconPassword,
      `mp_teamname_1 "${match.teamA.name}"`);
    await rconService.sendCommand(server.host, rconPort, server.rconPassword,
      `mp_teamname_2 "${match.teamB.name}"`);

    for (const p of match.teamA.players) {
      await rconService.sendCommand(server.host, rconPort, server.rconPassword,
        `addplayer "${p.steamId}" 1`);
    }
    for (const p of match.teamB.players) {
      await rconService.sendCommand(server.host, rconPort, server.rconPassword,
        `addplayer "${p.steamId}" 2`);
    }

    await rconService.changeMap(server.host, rconPort, server.rconPassword, match.selectedMap);

    const teamAPipe = match.teamA.players.map((p) => p.steamId).join('|');
    const teamBPipe = match.teamB.players.map((p) => p.steamId).join('|');

    setTimeout(async () => {
      try {
        await rconService.beginMatchTracker(
          server.host,
          rconPort,
          server.rconPassword,
          matchId,
          match.config.maxRounds,
        );
        await rconService.setMatchTrackerRoster(
          server.host,
          rconPort,
          server.rconPassword,
          teamAPipe,
          teamBPipe,
        );
        await rconService.startMatch(server.host, rconPort, server.rconPassword);
      } catch {}
    }, 15000);

    stateStore.persist();
    return match;
  }

  async endMatch(matchId: string): Promise<Match> {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');

    if (match.serverId) {
      const server = serverManager.getServer(match.serverId);
      if (server) {
        const rconPort = resolveRconPort(server);
        try {
          await rconService.clearMatchTracker(
            server.host,
            rconPort,
            server.rconPassword,
          );
        } catch {}
      }
    }

    match.status = 'finished';
    stateStore.persist();
    return match;
  }

  cancelMatch(matchId: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    match.status = 'cancelled';
    stateStore.persist();
    return match;
  }
}

export const matchManager = new MatchManager();
