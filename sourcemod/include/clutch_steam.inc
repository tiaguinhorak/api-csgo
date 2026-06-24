#if defined _clutch_steam_included_
    #endinput
#endif
#define _clutch_steam_included_

/**
 * Steam2 for SQLite lookups. Validated auth first; unvalidated fallback when status
 * already shows STEAM_x but GetClientAuthId(..., true) fails (LAN / post-restart).
 */
stock bool ClutchGetClientSteam2(int client, char[] steamId, int maxlen) {
    if (GetClientAuthId(client, AuthId_Steam2, steamId, maxlen, true)) {
        return true;
    }
    return GetClientAuthId(client, AuthId_Steam2, steamId, maxlen, false);
}
