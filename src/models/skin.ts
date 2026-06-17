export type Wear = 'factory_new' | 'minimal_wear' | 'field_tested' | 'well_worn' | 'battle_scarred';
export type Rarity = 'consumer' | 'industrial' | 'mil_spec' | 'restricted' | 'classified' | 'covert' | 'rare';

export interface WeaponSkin {
  id: string;
  weaponId: string;
  weaponName: string;
  paintkit: number;
  paintkitName: string;
  rarity: Rarity;
  category: string;
  imageUrl?: string;
}

export interface PlayerSkin {
  id: string;
  steamId: string;
  skinId: string;
  wear: Wear;
  seed: number;
  stattrak: boolean;
  stattrakCount: number;
  nametag?: string;
  equipped: boolean;
  acquiredAt: string;
}

export interface SkinLoadout {
  steamId: string;
  loadout: Record<string, {
    skinId: string;
    wear: Wear;
    seed: number;
    stattrak: boolean;
    nametag?: string;
  }>;
}

export const WEAPON_SLOTS = [
  'weapon_ak47', 'weapon_m4a1', 'weapon_m4a1_silencer', 'weapon_awp',
  'weapon_deagle', 'weapon_usp_silencer', 'weapon_glock', 'weapon_mp9',
  'weapon_mac10', 'weapon_famas', 'weapon_galilar', 'weapon_ssg08',
  'weapon_scar20', 'weapon_g3sg1', 'weapon_p250', 'weapon_fiveseven',
  'weapon_tec9', 'weapon_cz75a', 'weapon_elite', 'weapon_p2000',
  'weapon_xm1014', 'weapon_mag7', 'weapon_nova', 'weapon_sawedoff',
  'weapon_bizon', 'weapon_p90', 'weapon_ump45', 'weapon_mp7',
  'weapon_negev', 'weapon_m249', 'weapon_sg556', 'weapon_aug',
  'weapon_knife', 'weapon_gloves',
];

export const SKIN_WEAR_VALUES: Record<Wear, number> = {
  factory_new: 0.07,
  minimal_wear: 0.15,
  field_tested: 0.38,
  well_worn: 0.45,
  battle_scarred: 1.00,
};
