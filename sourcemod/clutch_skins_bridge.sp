#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#undef REQUIRE_PLUGIN
#tryinclude <weapons>

#define PLUGIN_VERSION "2.0.0"
#define KV_ROOT "ClutchSkins"

ConVar g_cvSkinsFile;
ConVar g_cvRefreshSeconds;
ConVar g_cvDebug;
ConVar g_cvWeaponsDb;
ConVar g_cvWeaponsTablePrefix;
ConVar g_cvSyncWeaponsDb;

Handle g_hSkinsKv = null;
Database g_hWeaponsDb = null;
char g_sSkinsFile[PLATFORM_MAX_PATH];
char g_sTablePrefix[16];
bool g_bLoggedMissingLoadout[MAXPLAYERS + 1];
int g_iItemIdHigh = 16384;

public Plugin myinfo = {
    name = "Clutch Skins Bridge",
    author = "clutchclube",
    description = "Applies web-equipped skins via weapons DB + kgns weapons",
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
    g_cvWeaponsDb = CreateConVar(
        "clutch_weapons_db",
        "storage-local",
        "Database connection for kgns weapons plugin (databases.cfg)",
        FCVAR_NOTIFY
    );
    g_cvWeaponsTablePrefix = CreateConVar(
        "clutch_weapons_table_prefix",
        "",
        "Table prefix for kgns weapons (same as sm_weapons_table_prefix)",
        FCVAR_NOTIFY
    );
    g_cvSyncWeaponsDb = CreateConVar(
        "clutch_weapons_sync_db",
        "1",
        "Sync clutch_skins.txt into weapons SQLite (1 = yes)",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    AutoExecConfig(true, "clutch_skins_bridge");

    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));

    RegAdminCmd("sm_reloadclutchskins", Command_ReloadSkins, ADMFLAG_ROOT, "Reload clutch_skins.txt");
    RegAdminCmd("sm_clutch_applyskins", Command_ApplySkins, ADMFLAG_ROOT, "Re-apply clutch skins to all players");

    ConnectWeaponsDatabase();
    LoadSkinsFile(true);
    CreateTimer(g_cvRefreshSeconds.FloatValue, Timer_RefreshSkins, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnAllPluginsLoaded() {
    if (!LibraryExists("weapons")) {
        LogMessage("[Clutch] weapons.smx not loaded — knife models need kgns Weapons & Knives + PTaH");
    }
}

public void OnPluginEnd() {
    if (g_hSkinsKv != null) {
        delete g_hSkinsKv;
        g_hSkinsKv = null;
    }
    if (g_hWeaponsDb != null) {
        delete g_hWeaponsDb;
        g_hWeaponsDb = null;
    }
}

void ConnectWeaponsDatabase() {
    if (g_hWeaponsDb != null) {
        delete g_hWeaponsDb;
        g_hWeaponsDb = null;
    }

    char dbName[64];
    g_cvWeaponsDb.GetString(dbName, sizeof(dbName));
    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));

    Database.Connect(WeaponsDatabaseConnected, dbName);
}

public void WeaponsDatabaseConnected(Database database, const char[] error, any data) {
    if (database == null) {
        LogError("[Clutch] weapons DB connect failed: %s", error);
        return;
    }

    g_hWeaponsDb = database;
    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Connected to weapons database");
    }
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

    BuildPath(Path_SM, path, maxlen, relative);
}

void LoadSkinsFile(bool announce) {
    g_cvSkinsFile.GetString(g_sSkinsFile, sizeof(g_sSkinsFile));

    char path[PLATFORM_MAX_PATH];
    ResolveSkinsFilePath(g_sSkinsFile, path, sizeof(path));

    if (!FileExists(path)) {
        char fallback[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, fallback, sizeof(fallback), "data/clutch_skins.txt");
        if (!StrEqual(path, fallback, false) && FileExists(fallback)) {
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

    if (g_cvSyncWeaponsDb.BoolValue && g_hWeaponsDb != null) {
        SyncAllLoadoutsToWeaponsDatabase();
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
    CreateTimer(0.25, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(3.0, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
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

void WeaponKeyToDbColumn(const char[] weaponKey, char[] column, int maxlen) {
    if (StrContains(weaponKey, "weapon_", false) == 0) {
        strcopy(column, maxlen, weaponKey[7]);
    } else {
        strcopy(column, maxlen, weaponKey);
    }
}

int KnifeIndexFromWeaponKey(const char[] weaponKey) {
    if (StrEqual(weaponKey, "weapon_knife", false)) {
        return 0;
    }
    if (StrEqual(weaponKey, "weapon_knife_karambit", false)) {
        return 33;
    }
    if (StrEqual(weaponKey, "weapon_knife_m9_bayonet", false)) {
        return 34;
    }
    if (StrEqual(weaponKey, "weapon_bayonet", false)) {
        return 35;
    }
    if (StrEqual(weaponKey, "weapon_knife_survival_bowie", false)) {
        return 36;
    }
    if (StrEqual(weaponKey, "weapon_knife_butterfly", false)) {
        return 37;
    }
    if (StrEqual(weaponKey, "weapon_knife_flip", false)) {
        return 38;
    }
    if (StrEqual(weaponKey, "weapon_knife_push", false)) {
        return 39;
    }
    if (StrEqual(weaponKey, "weapon_knife_tactical", false)) {
        return 40;
    }
    if (StrEqual(weaponKey, "weapon_knife_falchion", false)) {
        return 41;
    }
    if (StrEqual(weaponKey, "weapon_knife_gut", false)) {
        return 42;
    }
    if (StrEqual(weaponKey, "weapon_knife_ursus", false)) {
        return 43;
    }
    if (StrEqual(weaponKey, "weapon_knife_gypsy_jackknife", false)) {
        return 44;
    }
    if (StrEqual(weaponKey, "weapon_knife_stiletto", false)) {
        return 45;
    }
    if (StrEqual(weaponKey, "weapon_knife_widowmaker", false)) {
        return 46;
    }
    if (StrEqual(weaponKey, "weapon_knife_css", false)) {
        return 48;
    }
    if (StrEqual(weaponKey, "weapon_knife_cord", false)) {
        return 49;
    }
    if (StrEqual(weaponKey, "weapon_knife_canis", false)) {
        return 50;
    }
    if (StrEqual(weaponKey, "weapon_knife_outdoor", false)) {
        return 51;
    }
    if (StrEqual(weaponKey, "weapon_knife_skeleton", false)) {
        return 52;
    }
    return -1;
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

bool IsPaintableWeaponEntity(int entity) {
    return entity > MaxClients
        && IsValidEntity(entity)
        && HasEntProp(entity, Prop_Send, "m_nFallbackPaintKit");
}

void SetClutchWeaponProps(
    int client,
    int weapon,
    int paintkit,
    float wear,
    int seed,
    int stattrak,
    const char[] nametag,
    bool isKnife
) {
    if (!IsPaintableWeaponEntity(weapon) || paintkit <= 0) {
        return;
    }

    SetEntProp(weapon, Prop_Send, "m_iItemIDLow", -1);
    SetEntProp(weapon, Prop_Send, "m_iItemIDHigh", g_iItemIdHigh++);
    SetEntProp(weapon, Prop_Send, "m_nFallbackPaintKit", paintkit);

    float appliedWear = wear;
    if (appliedWear == 0.0) {
        appliedWear = 0.000001;
    } else if (appliedWear >= 1.0) {
        appliedWear = 0.999999;
    }
    SetEntPropFloat(weapon, Prop_Send, "m_flFallbackWear", appliedWear);

    int appliedSeed = seed >= 0 ? seed : GetRandomInt(0, 8192);
    SetEntProp(weapon, Prop_Send, "m_nFallbackSeed", appliedSeed);

    if (isKnife) {
        SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 3);
        if (stattrak >= 0) {
            SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", stattrak > 0 ? stattrak : -1);
        }
    } else if (stattrak > 0) {
        SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", stattrak);
        SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 9);
    } else {
        SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 0);
    }

    if (nametag[0] != '\0') {
        int offset = FindSendPropInfo("CBaseAttributableItem", "m_szCustomName");
        if (offset != -1) {
            SetEntDataString(weapon, offset, nametag, 128);
        }
    }

    SetEntProp(weapon, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
    if (HasEntProp(weapon, Prop_Send, "m_hOwnerEntity")) {
        SetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity", client);
    }
    if (HasEntProp(weapon, Prop_Send, "m_hPrevOwner")) {
        SetEntPropEnt(weapon, Prop_Send, "m_hPrevOwner", -1);
    }
}

void ClutchSetClientKnife(int client, const char[] knifeClass) {
#if defined _weapons_included_
    if (LibraryExists("weapons")) {
        Weapons_SetClientKnife(client, knifeClass, false);
    }
#endif
}

void SyncAllLoadoutsToWeaponsDatabase() {
    if (g_hSkinsKv == null || g_hWeaponsDb == null) {
        return;
    }

    KvRewind(g_hSkinsKv);
    if (!KvGotoFirstSubKey(g_hSkinsKv, false)) {
        return;
    }

    do {
        char steamId[32];
        KvGetSectionName(g_hSkinsKv, steamId, sizeof(steamId));
        SyncSteamLoadoutToWeaponsDatabase(steamId);
    } while (KvGotoNextKey(g_hSkinsKv, false));

    KvRewind(g_hSkinsKv);
}

void SyncSteamLoadoutToWeaponsDatabase(const char[] steamId) {
    if (g_hSkinsKv == null || g_hWeaponsDb == null) {
        return;
    }

    KvRewind(g_hSkinsKv);
    if (!KvJumpToKey(g_hSkinsKv, steamId)) {
        return;
    }

    char escapedSteam[64];
    g_hWeaponsDb.Escape(steamId, escapedSteam, sizeof(escapedSteam));

    char updates[4096];
    int updateLen = 0;
    int knifeIndex = -1;

    if (KvGotoFirstSubKey(g_hSkinsKv, false)) {
        do {
            char weaponKey[64];
            KvGetSectionName(g_hSkinsKv, weaponKey, sizeof(weaponKey));

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
            int stattrak = KvGetNum(g_hSkinsKv, "stattrak", 0);
            char nametag[64];
            KvGetString(g_hSkinsKv, "nametag", nametag, sizeof(nametag), "");

            char column[48];
            WeaponKeyToDbColumn(weaponKey, column, sizeof(column));

            char escapedTag[128];
            g_hWeaponsDb.Escape(nametag, escapedTag, sizeof(escapedTag));

            updateLen += Format(
                updates[updateLen],
                sizeof(updates) - updateLen,
                "%s%s=%d, %s_float=%.4f, %s_trak=%d, %s_seed=%d, %s_tag='%s'",
                updateLen > 0 ? ", " : "",
                column,
                paintkit,
                column,
                wear,
                column,
                stattrak > 0 ? 1 : 0,
                column,
                seed >= 0 ? seed : -1,
                column,
                escapedTag
            );

            if (IsMeleeWeaponKey(weaponKey)) {
                int idx = KnifeIndexFromWeaponKey(weaponKey);
                if (idx >= 0) {
                    knifeIndex = idx;
                }
            }
        } while (KvGotoNextKey(g_hSkinsKv, false));
        KvGoBack(g_hSkinsKv);
    }

    if (knifeIndex >= 0) {
        updateLen += Format(
            updates[updateLen],
            sizeof(updates) - updateLen,
            "%sknife=%d",
            updateLen > 0 ? ", " : "",
            knifeIndex
        );
    }

    KvGoBack(g_hSkinsKv);

    if (updateLen == 0) {
        return;
    }

    char insertQuery[128];
    Format(
        insertQuery,
        sizeof(insertQuery),
        "INSERT OR IGNORE INTO %sweapons (steamid) VALUES ('%s')",
        g_sTablePrefix,
        escapedSteam
    );
    g_hWeaponsDb.Query(T_SyncWeaponsDbCallback, insertQuery);

    char query[4608];
    Format(
        query,
        sizeof(query),
        "UPDATE %sweapons SET %s WHERE steamid='%s'",
        g_sTablePrefix,
        updates,
        escapedSteam
    );
    g_hWeaponsDb.Query(T_SyncWeaponsDbCallback, query);

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Synced weapons DB for %s", steamId);
    }
}

public void T_SyncWeaponsDbCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[Clutch] weapons DB query failed: %s", error);
    }
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

    char steamId[32];
    GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true);

    if (g_cvSyncWeaponsDb.BoolValue && g_hWeaponsDb != null) {
        SyncSteamLoadoutToWeaponsDatabase(steamId);
    }

    char knifeClass[64];
    knifeClass[0] = '\0';

    if (KvGotoFirstSubKey(g_hSkinsKv, false)) {
        do {
            char weaponKey[64];
            KvGetSectionName(g_hSkinsKv, weaponKey, sizeof(weaponKey));

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

            if (IsMeleeWeaponKey(weaponKey)) {
                int idx = KnifeIndexFromWeaponKey(weaponKey);
                if (idx >= 0) {
                    strcopy(knifeClass, sizeof(knifeClass), weaponKey);
                }
            }

            int weapon = FindPlayerWeapon(client, weaponKey);
            if (weapon != -1) {
                SetClutchWeaponProps(
                    client,
                    weapon,
                    paintkit,
                    wear,
                    seed,
                    stattrak,
                    nametag,
                    IsMeleeWeaponKey(weaponKey)
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

    if (knifeClass[0] != '\0') {
        ClutchSetClientKnife(client, knifeClass);
    }

    CS_UpdateClientModel(client);
}
