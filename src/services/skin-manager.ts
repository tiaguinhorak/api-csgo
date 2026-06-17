import { PlayerSkin, SkinLoadout, WeaponSkin, Wear, WEAPON_SLOTS, SKIN_WEAR_VALUES } from '../models/skin';
import { v4 as uuidv4 } from 'uuid';

class SkinManager {
  private skins: Map<string, PlayerSkin> = new Map();
  private weaponCatalog: Map<string, WeaponSkin> = new Map();
  private loadouts: Map<string, SkinLoadout> = new Map();

  // --- Weapon Skin Catalog ---

  registerWeaponSkin(skin: WeaponSkin): WeaponSkin {
    this.weaponCatalog.set(skin.id, skin);
    return skin;
  }

  getWeaponSkin(id: string): WeaponSkin | undefined {
    return this.weaponCatalog.get(id);
  }

  listWeaponSkins(weaponId?: string): WeaponSkin[] {
    const all = Array.from(this.weaponCatalog.values());
    return weaponId ? all.filter(s => s.weaponId === weaponId) : all;
  }

  // --- Player Skins ---

  giveSkin(steamId: string, skinId: string, wear: Wear, seed?: number, stattrak?: boolean, nametag?: string): PlayerSkin {
    const catalogSkin = this.weaponCatalog.get(skinId);
    if (!catalogSkin) throw new Error(`Skin ${skinId} not found in catalog`);

    const playerSkin: PlayerSkin = {
      id: uuidv4(),
      steamId,
      skinId,
      wear,
      seed: seed ?? Math.floor(Math.random() * 1000),
      stattrak: stattrak ?? false,
      stattrakCount: 0,
      nametag,
      equipped: false,
      acquiredAt: new Date().toISOString(),
    };

    const key = `${steamId}:${playerSkin.id}`;
    this.skins.set(key, playerSkin);
    return playerSkin;
  }

  getPlayerSkins(steamId: string): PlayerSkin[] {
    return Array.from(this.skins.values()).filter(s => s.steamId === steamId);
  }

  getPlayerSkin(id: string, steamId: string): PlayerSkin | undefined {
    return this.skins.get(`${steamId}:${id}`);
  }

  removePlayerSkin(id: string, steamId: string): boolean {
    return this.skins.delete(`${steamId}:${id}`);
  }

  // --- Loadout ---

  equipSkin(steamId: string, playerSkinId: string): SkinLoadout {
    const playerSkin = this.getPlayerSkin(playerSkinId, steamId);
    if (!playerSkin) throw new Error('Player skin not found');

    const catalogSkin = this.weaponCatalog.get(playerSkin.skinId);
    if (!catalogSkin) throw new Error('Catalog skin not found');

    let loadout = this.loadouts.get(steamId);
    if (!loadout) {
      loadout = { steamId, loadout: {} };
      this.loadouts.set(steamId, loadout);
    }

    loadout.loadout[catalogSkin.weaponId] = {
      skinId: playerSkin.id,
      wear: playerSkin.wear,
      seed: playerSkin.seed,
      stattrak: playerSkin.stattrak,
      nametag: playerSkin.nametag,
    };

    playerSkin.equipped = true;
    return loadout;
  }

  unequipSkin(steamId: string, weaponId: string): SkinLoadout {
    const loadout = this.loadouts.get(steamId);
    if (!loadout) throw new Error('No loadout found');

    // Find the player skin and mark as not equipped
    const equipped = loadout.loadout[weaponId];
    if (equipped) {
      const playerSkin = this.getPlayerSkin(equipped.skinId, steamId);
      if (playerSkin) playerSkin.equipped = false;
    }

    delete loadout.loadout[weaponId];
    return loadout;
  }

  getLoadout(steamId: string): SkinLoadout {
    let loadout = this.loadouts.get(steamId);
    if (!loadout) {
      loadout = { steamId, loadout: {} };
      this.loadouts.set(steamId, loadout);
    }
    return loadout;
  }

  getFullLoadoutData(steamId: string): Record<string, any> {
    const loadout = this.getLoadout(steamId);
    const result: Record<string, any> = {};

    for (const [weaponId, equipped] of Object.entries(loadout.loadout)) {
      const playerSkin = this.getPlayerSkin(equipped.skinId, steamId);
      if (playerSkin) {
        const catalogSkin = this.weaponCatalog.get(playerSkin.skinId);
        result[weaponId] = {
          paintkit: catalogSkin?.paintkit ?? 0,
          wear: SKIN_WEAR_VALUES[playerSkin.wear],
          seed: playerSkin.seed,
          stattrak: playerSkin.stattrak ? playerSkin.stattrakCount : -1,
          nametag: playerSkin.nametag ?? '',
        };
      }
    }

    return result;
  }

  // --- Export for plugin ---

  async exportLoadoutForPlugin(steamId: string): Promise<string> {
    const loadout = this.getFullLoadoutData(steamId);
    const lines: string[] = [];
    lines.push(`"${steamId}"`);

    for (const [weapon, data] of Object.entries(loadout)) {
      lines.push(`  "${weapon}"`);
      lines.push('  {');
      lines.push(`    "paintkit"    "${data.paintkit}"`);
      lines.push(`    "wear"        "${data.wear}"`);
      lines.push(`    "seed"        "${data.seed}"`);
      if (data.stattrak >= 0) {
        lines.push(`    "stattrak"    "${data.stattrak}"`);
      }
      if (data.nametag) {
        lines.push(`    "nametag"     "${data.nametag}"`);
      }
      lines.push('  }');
    }

    return lines.join('\n');
  }

  async exportAllForPlugin(): Promise<string> {
    const allSteamIds = new Set<string>();
    for (const [key] of this.skins) {
      const [steamId] = key.split(':');
      allSteamIds.add(steamId);
    }

    const sections: string[] = ['"Skins"'];
    for (const steamId of allSteamIds) {
      const loadout = await this.exportLoadoutForPlugin(steamId);
      sections.push(loadout);
    }

    return sections.join('\n\n');
  }

  // --- Pre-populate with default skins ---

  initializeDefaultSkins(): void {
    const defaultSkins: WeaponSkin[] = [
      { id: 'ak47_redline', weaponId: 'weapon_ak47', weaponName: 'AK-47', paintkit: 282, paintkitName: 'Redline', rarity: 'classified', category: 'rifle' },
      { id: 'ak47_vulcan', weaponId: 'weapon_ak47', weaponName: 'AK-47', paintkit: 151, paintkitName: 'Vulcan', rarity: 'covert', category: 'rifle' },
      { id: 'ak47_asiimov', weaponId: 'weapon_ak47', weaponName: 'AK-47', paintkit: 524, paintkitName: 'Asiimov', rarity: 'covert', category: 'rifle' },
      { id: 'm4a4_asiimov', weaponId: 'weapon_m4a1', weaponName: 'M4A4', paintkit: 255, paintkitName: 'Asiimov', rarity: 'classified', category: 'rifle' },
      { id: 'm4a4_dragon_king', weaponId: 'weapon_m4a1', weaponName: 'M4A4', paintkit: 530, paintkitName: 'Dragon King', rarity: 'classified', category: 'rifle' },
      { id: 'm4a1s_mecha', weaponId: 'weapon_m4a1_silencer', weaponName: 'M4A1-S', paintkit: 747, paintkitName: 'Mecha Industries', rarity: 'classified', category: 'rifle' },
      { id: 'm4a1s_hyper_beast', weaponId: 'weapon_m4a1_silencer', weaponName: 'M4A1-S', paintkit: 622, paintkitName: 'Hyper Beast', rarity: 'covert', category: 'rifle' },
      { id: 'awp_asiimov', weaponId: 'weapon_awp', weaponName: 'AWP', paintkit: 279, paintkitName: 'Asiimov', rarity: 'covert', category: 'sniper' },
      { id: 'awp_dragon_lore', weaponId: 'weapon_awp', weaponName: 'AWP', paintkit: 344, paintkitName: 'Dragon Lore', rarity: 'rare', category: 'sniper' },
      { id: 'awp_medusa', weaponId: 'weapon_awp', weaponName: 'AWP', paintkit: 396, paintkitName: 'Medusa', rarity: 'rare', category: 'sniper' },
      { id: 'deagle_blaze', weaponId: 'weapon_deagle', weaponName: 'Desert Eagle', paintkit: 38, paintkitName: 'Blaze', rarity: 'classified', category: 'pistol' },
      { id: 'deagle_code_red', weaponId: 'weapon_deagle', weaponName: 'Desert Eagle', paintkit: 848, paintkitName: 'Code Red', rarity: 'classified', category: 'pistol' },
      { id: 'usp_neo_noir', weaponId: 'weapon_usp_silencer', weaponName: 'USP-S', paintkit: 780, paintkitName: 'Neo-Noir', rarity: 'classified', category: 'pistol' },
      { id: 'usp_kill_confirmed', weaponId: 'weapon_usp_silencer', weaponName: 'USP-S', paintkit: 315, paintkitName: 'Kill Confirmed', rarity: 'covert', category: 'pistol' },
      { id: 'glock_water', weaponId: 'weapon_glock', weaponName: 'Glock-18', paintkit: 541, paintkitName: 'Water Elemental', rarity: 'classified', category: 'pistol' },
      { id: 'glock_neo_noir', weaponId: 'weapon_glock', weaponName: 'Glock-18', paintkit: 829, paintkitName: 'Neo-Noir', rarity: 'classified', category: 'pistol' },
      { id: 'knife_doppler', weaponId: 'weapon_knife', weaponName: 'Karambit', paintkit: 416, paintkitName: 'Doppler', rarity: 'rare', category: 'knife' },
      { id: 'knife_fade', weaponId: 'weapon_knife', weaponName: 'Karambit', paintkit: 409, paintkitName: 'Fade', rarity: 'rare', category: 'knife' },
    ];

    for (const skin of defaultSkins) {
      this.registerWeaponSkin(skin);
    }
  }
}

export const skinManager = new SkinManager();
