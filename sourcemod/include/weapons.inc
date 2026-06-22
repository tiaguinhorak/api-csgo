#if defined _weapons_included_
  #endinput
#endif
#define _weapons_included_

native void Weapons_GetClientKnife(int client, char[] sKnife, int Size);
native void Weapons_SetClientKnife(int client, const char[] sKnife, bool update);
/** Reload g_iSkins / g_iKnife from SQLite (added by clutch patch on weapons.smx). */
native void Weapons_ReloadClientData(int client);

forward Action Weapons_OnClientKnifeSelectPre(int client, int knifeId, char[] knifeName);
forward void Weapons_OnClientKnifeSelectPost(int client, int knifeId, char[] knifeName);
