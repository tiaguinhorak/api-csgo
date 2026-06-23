#if defined _clutch_gloves_included_
    #endinput
#endif
#define _clutch_gloves_included_

/** Reload glove row from SQLite into cache. Does not change visuals until spawn. */
native void ClutchGloves_RefreshClient(int client);
/** Force visual apply from cache (admin); normal flow uses player_spawn only. */
native void ClutchGloves_ApplyClient(int client);
native bool ClutchGloves_IsClientUsingGloves(int client);

/**
 * Called after glove wearable is applied on spawn (group and paintkit > 0).
 */
forward void ClutchGloves_OnClientApplied(int client, int group, int paintkit);
