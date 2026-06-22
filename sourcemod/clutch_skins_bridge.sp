#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "1.1.4"
#define KV_ROOT "ClutchSkins"

ConVar g_cvSkinsFile;
ConVar g_cvRefreshSeconds;
ConVar g_cvDebug;
Handle g_hSkinsKv = null;
char g_sSkinsFile[PLATFORM_MAX_PATH];
bool g_bLoggedMissingLoadout[MAXPLAYERS + 1];

public Plugin myinfo = {
    name = "Clutch Skins Bridge",
    author = "clutchclube",
    description = "Applies web-equipped skins from clutch_skins.txt",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com"
};

public void OnPluginStart() {
    g_cvSkinsFile = CreateConVar(
        "clutch_skins_file",
        "data/clutch_skins.txt",
        "KeyValues export path (relative to addons/sourcemod/, or absolute)",
        FCVAR_NOTIFY
    );
    g_cvRefreshSeconds = CreateConVar(
        "clutch_skins_refresh",
        "30.0",
        "Seconds between file reload checks",
        FCVAR_NOTIFY,
        true,
        5.0,
        true,
        300.0
    );
    g_cvDebug = CreateConVar(
        "clutch_skins_debug",
        "0",
        "Log skin apply details (1 = yes)",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    AutoExecConfig(true, "clutch_skins_bridge");

    RegAdminCmd("sm_reloadclutchskins", Command_ReloadSkins, ADMFLAG_ROOT, "Reload clutch_skins.txt");
    RegAdminCmd("sm_clutch_applyskins", Command_ApplySkins, ADMFLAG_ROOT, "Re-apply clutch skins to all players");

    LoadSkinsFile(true);
    CreateTimer(g_cvRefreshSeconds.FloatValue, Timer_RefreshSkins, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart() {
    LoadSkinsFile(true);
}

public Action Timer_RefreshSkins(Handle timer) {
    LoadSkinsFile(false);
    return Plugin_Continue;
}

public Action Command_ReloadSkins(int client, int args) {
    LoadSkinsFile(true);
    ReplyToCommand(client, "[Clutch] clutch_skins.txt recarregado.");
    return Plugin_Handled;
}

public Action Command_ApplySkins(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            ScheduleApplyClientSkins(i);
        }
    }
    ReplyToCommand(client, "[Clutch] Reaplicando skins nos jogadores.");
    return Plugin_Handled;
}

void ResolveSkinsFilePath(const char[] configured, char[] path, int maxlen) {
    char relative[PLATFORM_MAX_PATH];
    strcopy(relative, sizeof(relative), configured);

    if (StrContains(relative, "addons/sourcemod/", false) == 0) {
        strcopy(relative, sizeof(relative), configured[17]);
    }

    if (relative[0] == '/') {
        strcopy(path, maxlen, relative);
        return;
    }

    // Relative paths resolve under addons/sourcemod/ (e.g. data/clutch_skins.txt).
    BuildPath(Path_SM, path, maxlen, relative);
}

void LoadSkinsFile(bool announce) {
    g_cvSkinsFile.GetString(g_sSkinsFile, sizeof(g_sSkinsFile));

    char path[PLATFORM_MAX_PATH];
    ResolveSkinsFilePath(g_sSkinsFile, path, sizeof(path));

    if (!FileExists(path)) {
        char fallback[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, fallback, sizeof(fallback), "data/clutch_skins.txt");
        if (StrEqual(path, fallback, false) == false && FileExists(fallback)) {
            strcopy(path, sizeof(path), fallback);
        }
    }

    if (!FileExists(path)) {
        if (announce) {
            LogMessage(
                "[Clutch] Skins file missing. Resolved: %s | configured: %s",
                path,
                g_sSkinsFile
            );
        }
        return;
    }

    Handle kv = CreateKeyValues(KV_ROOT);
    if (!FileToKeyValues(kv, path)) {
        delete kv;
        LogError("[Clutch] Failed to parse %s", path);
        return;
    }

    if (g_hSkinsKv != null) {
        delete g_hSkinsKv;
    }
    g_hSkinsKv = kv;

    if (announce) {
        LogMessage("[Clutch] Loaded skins from %s", path);
    }

    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client)) {
            ScheduleApplyClientSkins(client);
        }
    }
}

public void OnClientDisconnect(int client) {
    g_bLoggedMissingLoadout[client] = false;
}

public void OnClientPutInServer(int client) {
    if (IsFakeClient(client)) {
        return;
    }
    ScheduleApplyClientSkins(client);
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }
    ScheduleApplyClientSkins(client);
}

void ScheduleApplyClientSkins(int client) {
    int userid = GetClientUserId(client);
    RequestFrame(ApplyClientSkinsFrame, userid);
    CreateTimer(0.2, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.65, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.35, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(2.75, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(4.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(6.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(8.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(10.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplySkinsDelayed(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0) {
        ApplyClientSkins(client);
    }
    return Plugin_Stop;
}

bool JumpToPlayerLoadoutKv(int client) {
    KvRewind(g_hSkinsKv);

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        return false;
    }

    if (KvJumpToKey(g_hSkinsKv, steamId)) {
        return true;
    }

    // CS:GO often returns STEAM_1:x:y; site export uses STEAM_0:x:y (same account).
    if (steamId[6] == '1') {
        steamId[6] = '0';
        if (KvJumpToKey(g_hSkinsKv, steamId)) {
            return true;
        }
    } else if (steamId[6] == '0') {
        steamId[6] = '1';
        if (KvJumpToKey(g_hSkinsKv, steamId)) {
            return true;
        }
    }

    return false;
}

bool IsMeleeWeaponKey(const char[] weaponKey) {
    return StrContains(weaponKey, "knife", false) != -1
        || StrContains(weaponKey, "bayonet", false) != -1;
}

bool IsMeleeClassname(const char[] classname) {
    return StrContains(classname, "knife", false) != -1
        || StrContains(classname, "bayonet", false) != -1;
}

int FindPlayerWeapon(int client, const char[] weaponKey) {
    bool matchMelee = IsMeleeWeaponKey(weaponKey);

    for (int slot = 0; slot <= 5; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon == -1) {
            continue;
        }

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));

        if (matchMelee) {
            if (IsMeleeClassname(classname)) {
                return weapon;
            }
            continue;
        }

        if (StrEqual(classname, weaponKey, false)) {
            return weapon;
        }
    }

    return -1;
}

void ApplyWeaponSkinEntity(
    int client,
    int weapon,
    int paintkit,
    float wear,
    int seed,
    int stattrak,
    const char[] nametag
) {
    SetEntProp(weapon, Prop_Send, "m_iItemIDHigh", -1);
    SetEntProp(weapon, Prop_Send, "m_iItemIDLow", -1);
    SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 4);
    SetEntProp(weapon, Prop_Send, "m_nFallbackPaintKit", paintkit);
    SetEntPropFloat(weapon, Prop_Send, "m_flFallbackWear", wear);
    SetEntProp(weapon, Prop_Send, "m_nFallbackSeed", seed);

    if (stattrak >= 0) {
        SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", stattrak);
    }

    if (nametag[0] != '\0') {
        SetEntPropString(weapon, Prop_Send, "m_szCustomName", nametag);
    }

    int accountId = GetSteamAccountID(client);
    SetEntProp(weapon, Prop_Send, "m_OriginalOwnerXuidLow", accountId);
    SetEntProp(weapon, Prop_Send, "m_OriginalOwnerXuidHigh", 0);
    SetEntProp(weapon, Prop_Send, "m_iAccountID", accountId);
}

void ApplySkinToWeaponWorldModel(
    int client,
    int weapon,
    int paintkit,
    float wear,
    int seed,
    int stattrak,
    const char[] nametag
) {
    // Dedicated servers have no player viewmodels — only world weapon entities.
    if (!HasEntProp(weapon, Prop_Send, "m_hWeaponWorldModel")) {
        return;
    }

    int worldModel = GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel");
    if (worldModel <= MaxClients) {
        return;
    }

    ApplyWeaponSkinEntity(client, worldModel, paintkit, wear, seed, stattrak, nametag);
}

public void ApplyClientSkinsFrame(any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0) {
        ApplyClientSkins(client);
    }
}

void ApplyClientSkins(int client) {
    if (g_hSkinsKv == null || !IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    if (!JumpToPlayerLoadoutKv(client)) {
        if (!g_bLoggedMissingLoadout[client]) {
            char steamId[32];
            if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
                LogMessage("[Clutch] Sem loadout no arquivo para %s (%N)", steamId, client);
            }
            g_bLoggedMissingLoadout[client] = true;
        }
        return;
    }

    if (KvGotoFirstSubKey(g_hSkinsKv, false)) {
        do {
            char weaponKey[64];
            KvGetSectionName(g_hSkinsKv, weaponKey, sizeof(weaponKey));

            // Gloves not supported in v1 — skip silently.
            if (StrContains(weaponKey, "gloves", false) != -1
                || StrContains(weaponKey, "handwraps", false) != -1) {
                continue;
            }

            int paintkit = KvGetNum(g_hSkinsKv, "paintkit", 0);
            if (paintkit <= 0) {
                continue;
            }

            float wear = KvGetFloat(g_hSkinsKv, "wear", 0.15);
            int seed = KvGetNum(g_hSkinsKv, "seed", 0);
            int stattrak = KvGetNum(g_hSkinsKv, "stattrak", -1);
            char nametag[64];
            KvGetString(g_hSkinsKv, "nametag", nametag, sizeof(nametag), "");

            int weapon = FindPlayerWeapon(client, weaponKey);
            if (weapon != -1) {
                ApplyWeaponSkinEntity(client, weapon, paintkit, wear, seed, stattrak, nametag);
                ApplySkinToWeaponWorldModel(
                    client,
                    weapon,
                    paintkit,
                    wear,
                    seed,
                    stattrak,
                    nametag
                );
                if (g_cvDebug.BoolValue) {
                    char classname[64];
                    GetEntityClassname(weapon, classname, sizeof(classname));
                    LogMessage(
                        "[Clutch] Applied %s paintkit %d on %s for %N",
                        weaponKey,
                        paintkit,
                        classname,
                        client
                    );
                }
            } else if (g_cvDebug.BoolValue) {
                LogMessage("[Clutch] Weapon not found for key %s (%N)", weaponKey, client);
            }
        } while (KvGotoNextKey(g_hSkinsKv, false));
        KvGoBack(g_hSkinsKv);
    }

    KvGoBack(g_hSkinsKv);

    CS_UpdateClientModel(client);
}

public void OnPluginEnd() {
    if (g_hSkinsKv != null) {
        delete g_hSkinsKv;
        g_hSkinsKv = null;
    }
}
