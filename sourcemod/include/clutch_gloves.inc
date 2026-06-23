#if defined _clutch_gloves_included_
    #endinput
#endif
#define _clutch_gloves_included_

native void ClutchGloves_RefreshClient(int client);
native void ClutchGloves_ApplyClient(int client);
native bool ClutchGloves_IsClientUsingGloves(int client);

/**
 * Called after glove wearable is applied (group and paintkit > 0).
 */
forward void ClutchGloves_OnClientApplied(int client, int group, int paintkit);
