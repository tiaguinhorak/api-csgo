#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "1.0.6"
#define KV_ROOT "ClutchSkins"

ConVar g_cvSkinsFile;
ConVar g_cvRefreshSeconds;
Handle g_hSkinsKv = null;
char g_sSkinsFile[PLATFORM_MAX_PATH];

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

    AutoExecConfig(true, "clutch_skins_bridge");

    RegAdminCmd("sm_reloadclutchskins", Command_ReloadSkins, ADMFLAG_ROOT, "Reload clutch_skins.txt");

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

    if (StrContains(relative, "csgo/", false) == 0 || StrContains(relative, "csgo\\", false) == 0) {
        BuildPath(Path_Mod, path, maxlen, relative);
        return;
    }

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
            RequestFrame(ApplyClientSkinsFrame, GetClientUserId(client));
        }
    }
}

public void OnClientPutInServer(int client) {
    if (IsFakeClient(client)) {
        return;
    }
    RequestFrame(ApplyClientSkinsFrame, GetClientUserId(client));
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }
    int userid = GetClientUserId(client);
    RequestFrame(ApplyClientSkinsFrame, userid);
    CreateTimer(0.15, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.6, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
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

    return KvJumpToKey(g_hSkinsKv, steamId);
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
        return;
    }

    if (KvGotoFirstSubKey(g_hSkinsKv, false)) {
        do {
            char weaponKey[64];
            KvGetSectionName(g_hSkinsKv, weaponKey, sizeof(weaponKey));

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
            }
        } while (KvGotoNextKey(g_hSkinsKv, false));
        KvGoBack(g_hSkinsKv);
    }

    KvGoBack(g_hSkinsKv);
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
}

int FindPlayerWeapon(int client, const char[] weaponKey) {
    bool matchKnife = StrContains(weaponKey, "knife", false) != -1;

    for (int slot = 0; slot <= 5; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon == -1) {
            continue;
        }

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));

        if (matchKnife) {
            if (StrContains(classname, "knife", false) != -1) {
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

public void OnPluginEnd() {
    if (g_hSkinsKv != null) {
        delete g_hSkinsKv;
        g_hSkinsKv = null;
    }
}
