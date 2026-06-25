#if defined _csgo_weaponstickers_included_
  #endinput
#endif
#define _csgo_weaponstickers_included_

/**
 * csgo_weaponstickers.smx — applies sticker attrs via game SDK (reliable FP/world render).
 * Bridge calls this when the plugin is loaded; falls back to PTaH attrs otherwise.
 */
native bool CS_SetWeaponSticker(int client, int weapon, int slot, int defIndex, float wear, float rotation = 0.0);
