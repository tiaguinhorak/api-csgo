import { Match, CreateMatchDTO, MatchStatus, VetoAction, StartMatchDTO } from '../models/match';
import { getAvailableMaps, VETO_STEPS, VetoStep } from '../models/veto';
import { GameServer } from '../models/server';
import { config } from '../config';
import { v4 as uuidv4 } from 'uuid';
import { rconService } from './rcon';

class MatchManager {
  private matches: Map<string, Match> = new Map();

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
    return match;
  }

  getMatch(id: string): Match | undefined {
    return this.matches.get(id);
  }

  listMatches(status?: MatchStatus): Match[] {
    const all = Array.from(this.matches.values());
    if (status) {
      return all.filter(m => m.status === status);
    }
    return all;
  }

  startVeto(matchId: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status !== 'waiting_players') throw new Error('Invalid match status');

    match.status = 'veto';
    // If first step is "random" (decider), handle it immediately
    this.processNextAutoStep(match);
    return match;
  }

  private processNextAutoStep(match: Match): void {
    const stepIndex = match.vetoHistory.length;
    if (stepIndex >= VETO_STEPS.length) {
      match.status = 'ready';
      return;
    }

    const step = VETO_STEPS[stepIndex];
    if (step.action === 'random') {
      const used = match.vetoHistory.map(v => v.map);
      const available = getAvailableMaps(match.mapPool, used, []);
      if (available.length === 0) {
        match.status = 'ready';
        return;
      }
      const randomMap = available[Math.floor(Math.random() * available.length)];
      match.vetoHistory.push({
        team: step.team,
        action: 'random',
        map: randomMap,
        timestamp: new Date().toISOString(),
      });
      match.selectedMap = randomMap;
      match.status = 'ready';
    }
  }

  processVeto(matchId: string, team: 'A' | 'B', action: 'ban' | 'pick', map: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status !== 'veto') throw new Error('Veto is not active');

    const stepIndex = match.vetoHistory.length;
    if (stepIndex >= VETO_STEPS.length) {
      match.status = 'ready';
      throw new Error('Veto already completed');
    }

    const step = VETO_STEPS[stepIndex];
    if (step.team !== team) throw new Error(`It's ${step.team}'s turn`);
    if (step.action !== action) throw new Error(`Expected action: ${step.action}`);

    const used = match.vetoHistory.map(v => v.map);
    const available = getAvailableMaps(match.mapPool, used, []);
    if (!available.includes(map)) throw new Error(`Map ${map} is not available`);

    match.vetoHistory.push({ team, action, map, timestamp: new Date().toISOString() });

    if (action === 'pick') {
      match.selectedMap = map;
    }

    const nextStepIndex = match.vetoHistory.length;
    if (nextStepIndex >= VETO_STEPS.length) {
      match.status = 'ready';
    } else {
      const nextStep = VETO_STEPS[nextStepIndex];
      if (nextStep.action === 'random') {
        this.processNextAutoStep(match);
      }
    }

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

    const stepIndex = match.vetoHistory.length;
    const isComplete = stepIndex >= VETO_STEPS.length;
    const used = match.vetoHistory.map(v => v.map);
    const availableMaps = getAvailableMaps(match.mapPool, used, []);

    let currentStep: VetoStep | null = null;
    if (!isComplete && match.status === 'veto') {
      const step = VETO_STEPS[stepIndex];
      currentStep = { ...step, availableMaps };
    }

    return {
      history: match.vetoHistory,
      currentStep,
      availableMaps,
      isComplete,
    };
  }

  async startMatch(matchId: string, server: GameServer): Promise<Match> {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');
    if (match.status !== 'ready') throw new Error('Match is not ready');
    if (!match.selectedMap) throw new Error('No map selected');

    match.serverId = server.id;
    match.status = 'live';

    // Apply match config via RCON
    await rconService.setMatchConfig(server.host, server.rconPort, server.rconPassword, matchId);

    // Apply team config
    await rconService.sendCommand(server.host, server.rconPort, server.rconPassword,
      `mp_teamname_1 "${match.teamA.name}"`);
    await rconService.sendCommand(server.host, server.rconPort, server.rconPassword,
      `mp_teamname_2 "${match.teamB.name}"`);

    for (const player of match.teamA.players) {
      await rconService.sendCommand(server.host, server.rconPort, server.rconPassword,
        `addplayer "${player.steamId}" 1`);
    }
    for (const player of match.teamB.players) {
      await rconService.sendCommand(server.host, server.rconPort, server.rconPassword,
        `addplayer "${player.steamId}" 2`);
    }

    // Change to selected map
    await rconService.changeMap(server.host, server.rconPort, server.rconPassword, match.selectedMap);

    // End warmup after delay
    setTimeout(async () => {
      try {
        await rconService.startMatch(server.host, server.rconPort, server.rconPassword);
      } catch {}
    }, 15000);

    return match;
  }

  async endMatch(matchId: string): Promise<Match> {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');

    match.status = 'finished';
    return match;
  }

  cancelMatch(matchId: string): Match {
    const match = this.matches.get(matchId);
    if (!match) throw new Error('Match not found');

    match.status = 'cancelled';
    return match;
  }
}

export const matchManager = new MatchManager();
