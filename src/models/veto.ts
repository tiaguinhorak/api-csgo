export type VetoPhase = 'ban_a' | 'ban_b' | 'ban_a2' | 'ban_b2' | 'pick_a' | 'pick_b' | 'ban_a3' | 'ban_b3' | 'decider' | 'done';

export interface VetoStep {
  phase: VetoPhase;
  team: 'A' | 'B';
  action: 'ban' | 'pick' | 'random';
  availableMaps: string[];
}

export interface VetoRequest {
  matchId: string;
  action: 'ban' | 'pick';
  map: string;
}

export const VETO_STEPS: { phase: VetoPhase; team: 'A' | 'B'; action: 'ban' | 'pick' | 'random' }[] = [
  { phase: 'ban_a', team: 'B', action: 'ban' },
  { phase: 'ban_b', team: 'A', action: 'ban' },
  { phase: 'ban_a2', team: 'B', action: 'ban' },
  { phase: 'ban_b2', team: 'A', action: 'ban' },
  { phase: 'pick_a', team: 'A', action: 'pick' },
  { phase: 'pick_b', team: 'B', action: 'pick' },
  { phase: 'ban_a3', team: 'A', action: 'ban' },
  { phase: 'ban_b3', team: 'B', action: 'ban' },
  { phase: 'decider', team: 'A', action: 'random' },
];

export function getAvailableMaps(mapPool: string[], vetoedMaps: string[], pickedMaps: string[]): string[] {
  const removed = new Set([...vetoedMaps, ...pickedMaps]);
  return mapPool.filter(m => !removed.has(m));
}
