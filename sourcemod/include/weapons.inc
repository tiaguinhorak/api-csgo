#if defined _weapons_included_
  #endinput
#endif
#define _weapons_included_

native void Weapons_GetClientKnife(int client, char[] sKnife, int Size);
native void Weapons_SetClientKnife(int client, const char[] sKnife, bool update);

forward Action Weapons_OnClientKnifeSelectPre(int client, int knifeId, char[] knifeName);
forward void Weapons_OnClientKnifeSelectPost(int client, int knifeId, char[] knifeName);
