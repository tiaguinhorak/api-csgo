export type MatchStatus = 'waiting_players' | 'veto' | 'ready' | 'live' | 'finished' | 'cancelled';

export interface Match {
  id: string;
  roomId: string;
  teamA: Team;
  teamB: Team;
  mapPool: string[];
  vetoHistory: VetoAction[];
  status: MatchStatus;
  serverId?: string;
  selectedMap?: string;
  createdAt: string;
  config: MatchConfig;
}

export interface Team {
  name: string;
  players: Player[];
  side?: 'ct' | 't';
}

export interface Player {
  steamId: string;
  name: string;
}

export interface MatchConfig {
  gameType: number;
  gameMode: number;
  tickrate: number;
  tvDelay: number;
  enablePause: boolean;
  enableCoach: boolean;
  maxRounds: number;
  overtimeRounds: number;
}

export interface VetoAction {
  team: 'A' | 'B';
  action: 'ban' | 'pick' | 'random';
  map: string;
  timestamp: string;
}

export interface CreateMatchDTO {
  roomId: string;
  teamA: Team;
  teamB: Team;
  mapPool: string[];
  config?: Partial<MatchConfig>;
}

export interface StartMatchDTO {
  serverId: string;
}
