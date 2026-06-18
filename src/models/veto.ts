export type VetoPhase = string;
export type VetoActionType = 'ban' | 'pick' | 'random';

export interface VetoStepDef {
  phase: string;
  team: 'A' | 'B';
  action: VetoActionType;
}

export interface VetoStep {
  phase: string;
  team: 'A' | 'B';
  action: VetoActionType;
  availableMaps: string[];
}

export interface VetoRequest {
  matchId: string;
  action: 'ban' | 'pick';
  map: string;
}

export function generateVetoSteps(mapPool: string[]): VetoStepDef[] {
  const total = mapPool.length;
  const mapsAfterBans = 3;
  const banCount = total - mapsAfterBans;
  const steps: VetoStepDef[] = [];

  let banTeam: 'A' | 'B' = 'B';
  for (let i = 0; i < banCount; i++) {
    steps.push({ phase: `ban_${i + 1}`, team: banTeam, action: 'ban' });
    banTeam = banTeam === 'A' ? 'B' : 'A';
  }

  steps.push({ phase: 'pick_a', team: 'A', action: 'pick' });
  steps.push({ phase: 'pick_b', team: 'B', action: 'pick' });
  steps.push({ phase: 'decider', team: 'A', action: 'random' });

  return steps;
}

export function getAvailableMaps(mapPool: string[], usedMaps: string[]): string[] {
  const removed = new Set(usedMaps);
  return mapPool.filter(m => !removed.has(m));
}
