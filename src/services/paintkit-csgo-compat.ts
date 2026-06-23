import type { SyncWeaponPayload } from './weapons-db-map';
import {
  buildWsAllowlistSet,
  loadWsWeaponsAllowlist,
  wsAllowlistKey,
} from './ws-weapons-config';

export type CsgoCompatSkip = {
  weaponId: string;
  paintkit: number;
  reason: string;
};

/**
 * Drops CS2-only / non-!ws paintkits for catalog cfg generation.
 * Do NOT use for web player-sync — equipped loadouts are authoritative from the site DB.
 */
export async function filterCsgoCompatibleWeapons(
  weapons: SyncWeaponPayload[],
): Promise<{ weapons: SyncWeaponPayload[]; skipped: CsgoCompatSkip[] }> {
  const { entries } = await loadWsWeaponsAllowlist(false);
  const allowlist = buildWsAllowlistSet(entries);

  if (allowlist.size === 0) {
    return { weapons, skipped: [] };
  }

  const kept: SyncWeaponPayload[] = [];
  const skipped: CsgoCompatSkip[] = [];

  for (const weapon of weapons) {
    const key = wsAllowlistKey(weapon.weaponId, weapon.paintkit);
    if (allowlist.has(key)) {
      kept.push(weapon);
    } else {
      skipped.push({
        weaponId: weapon.weaponId,
        paintkit: weapon.paintkit,
        reason: 'CS2 or not in CS:GO !ws allowlist',
      });
    }
  }

  if (skipped.length > 0) {
    console.warn(
      `[csgo-compat] skipped ${skipped.length} non-CS:GO paintkit(s):`,
      skipped.map((s) => `${s.weaponId}:${s.paintkit}`).join(', '),
    );
  }

  return { weapons: kept, skipped };
}
