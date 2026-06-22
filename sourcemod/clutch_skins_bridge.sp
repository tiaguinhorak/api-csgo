#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#undef REQUIRE_PLUGIN
#tryinclude <weapons>

#define PLUGIN_VERSION "3.0.0"
#define CLUTCH_WEAPON_SLOTS 53

ConVar g_cvDebug;
ConVar g_cvWeaponsDb;
ConVar g_cvWeaponsTablePrefix;
ConVar g_cvRefreshSeconds;

Database g_hWeaponsDb = null;
char g_sTablePrefix[16];
bool g_bLoggedMissingLoadout[MAXPLAYERS + 1];
int g_iItemIdHigh = 16384;

char g_ClutchWeaponKeys[CLUTCH_WEAPON_SLOTS][32] = {
    "weapon_awp", "weapon_ak47", "weapon_m4a1", "weapon_m4a1_silencer",
    "weapon_deagle", "weapon_usp_silencer", "weapon_hkp2000", "weapon_glock",
    "weapon_elite", "weapon_p250", "weapon_cz75a", "weapon_fiveseven",
    "weapon_tec9", "weapon_revolver", "weapon_nova", "weapon_xm1014",
    "weapon_mag7", "weapon_sawedoff", "weapon_m249", "weapon_negev",
    "weapon_mp9", "weapon_mac10", "weapon_mp7", "weapon_ump45",
    "weapon_p90", "weapon_bizon", "weapon_famas", "weapon_galilar",
    "weapon_ssg08", "weapon_aug", "weapon_sg556", "weapon_scar20",
    "weapon_g3sg1", "weapon_knife_karambit", "weapon_knife_m9_bayonet",
    "weapon_bayonet", "weapon_knife_survival_bowie", "weapon_knife_butterfly",
    "weapon_knife_flip", "weapon_knife_push", "weapon_knife_tactical",
    "weapon_knife_falchion", "weapon_knife_gut", "weapon_knife_ursus",
    "weapon_knife_gypsy_jackknife", "weapon_knife_stiletto", "weapon_knife_widowmaker",
    "weapon_mp5sd", "weapon_knife_css", "weapon_knife_cord", "weapon_knife_canis",
    "weapon_knife_outdoor", "weapon_knife_skeleton"
};

char g_ClutchDbColumns[CLUTCH_WEAPON_SLOTS][32] = {
    "awp", "ak47", "m4a1", "m4a1_silencer", "deagle", "usp_silencer",
    "hkp2000", "glock", "elite", "p250", "cz75a", "fiveseven", "tec9",
    "revolver", "nova", "xm1014", "mag7", "sawedoff", "m249", "negev",
    "mp9", "mac10", "mp7", "ump45", "p90", "bizon", "famas", "galilar",
    "ssg08", "aug", "sg556", "scar20", "g3sg1", "knife_karambit",
    "knife_m9_bayonet", "bayonet", "knife_survival_bowie", "knife_butterfly",
    "knife_flip", "knife_push", "knife_tactical", "knife_falchion", "knife_gut",
    "knife_ursus", "knife_gypsy_jackknife", "knife_stiletto", "knife_widowmaker",
    "mp5sd", "knife_css", "knife_cord", "knife_canis", "knife_outdoor", "knife_skeleton"
};

public Plugin myinfo = {
    name = "Clutch Skins Bridge",
    author = "clutchclube",
    description = "Applies web-equipped skins from kgns weapons SQLite (API sync)",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com"
};

public void OnPluginStart() {
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
    g_cvRefreshSeconds = CreateConVar(
        "clutch_skins_refresh",
        "0.0",
        "Seconds between DB re-apply for online players (0 = disabled)",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        300.0
    );

    AutoExecConfig(true, "clutch_skins_bridge");

    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));

    RegAdminCmd("sm_reloadclutchskins", Command_ReloadSkins, ADMFLAG_ROOT, "Re-apply clutch skins from weapons DB");
    RegAdminCmd("sm_clutch_applyskins", Command_ApplySkins, ADMFLAG_ROOT, "Re-apply clutch skins to all players");

    ConnectWeaponsDatabase();

    float refresh = g_cvRefreshSeconds.FloatValue;
    if (refresh > 0.0) {
        CreateTimer(refresh, Timer_RefreshFromDb, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnAllPluginsLoaded() {
    if (!LibraryExists("weapons")) {
        LogMessage("[Clutch] weapons.smx not loaded — knife models need kgns Weapons & Knives + PTaH");
    }
}

public void OnPluginEnd() {
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
        LogMessage("[Clutch] Connected to weapons database (v%s DB-only mode)", PLUGIN_VERSION);
    }
}

public Action Timer_RefreshFromDb(Handle timer) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client)) {
            ApplyClientSkins(client);
        }
    }
    return Plugin_Continue;
}

public Action Command_ReloadSkins(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            ApplyClientSkins(i);
        }
    }
    ReplyToCommand(client, "[Clutch] Loadouts reaplicados do weapons DB.");
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

bool IsMeleeWeaponKey(const char[] weaponKey) {
    return StrContains(weaponKey, "knife", false) != -1
        || StrContains(weaponKey, "bayonet", false) != -1;
}

bool IsMeleeClassname(const char[] classname) {
    return StrContains(classname, "knife", false) != -1
        || StrContains(classname, "bayonet", false) != -1;
}

void KnifeClassFromIndex(int idx, char[] out, int maxlen) {
    switch (idx) {
        case 0: {
            strcopy(out, maxlen, "weapon_knife");
            return;
        }
        case 33: {
            strcopy(out, maxlen, "weapon_knife_karambit");
            return;
        }
        case 34: {
            strcopy(out, maxlen, "weapon_knife_m9_bayonet");
            return;
        }
        case 35: {
            strcopy(out, maxlen, "weapon_bayonet");
            return;
        }
        case 36: {
            strcopy(out, maxlen, "weapon_knife_survival_bowie");
            return;
        }
        case 37: {
            strcopy(out, maxlen, "weapon_knife_butterfly");
            return;
        }
        case 38: {
            strcopy(out, maxlen, "weapon_knife_flip");
            return;
        }
        case 39: {
            strcopy(out, maxlen, "weapon_knife_push");
            return;
        }
        case 40: {
            strcopy(out, maxlen, "weapon_knife_tactical");
            return;
        }
        case 41: {
            strcopy(out, maxlen, "weapon_knife_falchion");
            return;
        }
        case 42: {
            strcopy(out, maxlen, "weapon_knife_gut");
            return;
        }
        case 43: {
            strcopy(out, maxlen, "weapon_knife_ursus");
            return;
        }
        case 44: {
            strcopy(out, maxlen, "weapon_knife_gypsy_jackknife");
            return;
        }
        case 45: {
            strcopy(out, maxlen, "weapon_knife_stiletto");
            return;
        }
        case 46: {
            strcopy(out, maxlen, "weapon_knife_widowmaker");
            return;
        }
        case 48: {
            strcopy(out, maxlen, "weapon_knife_css");
            return;
        }
        case 49: {
            strcopy(out, maxlen, "weapon_knife_cord");
            return;
        }
        case 50: {
            strcopy(out, maxlen, "weapon_knife_canis");
            return;
        }
        case 51: {
            strcopy(out, maxlen, "weapon_knife_outdoor");
            return;
        }
        case 52: {
            strcopy(out, maxlen, "weapon_knife_skeleton");
            return;
        }
    }
    out[0] = '\0';
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
        char knife[64];
        strcopy(knife, sizeof(knife), knifeClass);
        Weapons_SetClientKnife(client, knife, false);
    }
#endif
}

void QueryPlayerLoadout(int client, const char[] steamId, int altAttempt) {
    if (g_hWeaponsDb == null) {
        ConnectWeaponsDatabase();
        return;
    }

    char escaped[64];
    g_hWeaponsDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);

    char query[256];
    Format(
        query,
        sizeof(query),
        "SELECT * FROM %sweapons WHERE steamid='%s' LIMIT 1",
        g_sTablePrefix,
        escaped
    );
    g_hWeaponsDb.Query(T_ApplyFromDbCallback, query, pack);
}

public void T_ApplyFromDbCallback(Database database, DBResultSet results, const char[] error, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int altAttempt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return;
    }

    if (results == null) {
        LogError("[Clutch] weapons DB query failed: %s", error);
        return;
    }

    if (!results.FetchRow()) {
        if (altAttempt == 0) {
            if (steamId[6] == '1') {
                steamId[6] = '0';
            } else if (steamId[6] == '0') {
                steamId[6] = '1';
            }
            QueryPlayerLoadout(client, steamId, 1);
            return;
        }

        if (!g_bLoggedMissingLoadout[client]) {
            LogMessage("[Clutch] Sem loadout no DB para %s (%N)", steamId, client);
            g_bLoggedMissingLoadout[client] = true;
        }
        return;
    }

    g_bLoggedMissingLoadout[client] = false;
    ApplyLoadoutFromDbRow(client, results);
}

int DbFieldNum(DBResultSet results, const char[] column) {
    int count = results.FieldCount;
    char name[48];

    for (int i = 0; i < count; i++) {
        results.FieldName(i, name, sizeof(name));
        if (StrEqual(name, column, false)) {
            return i;
        }
    }

    return -1;
}

int DbFetchInt(DBResultSet results, const char[] column, int defaultValue = 0) {
    int field = DbFieldNum(results, column);
    if (field == -1) {
        return defaultValue;
    }
    return results.FetchInt(field);
}

float DbFetchFloat(DBResultSet results, const char[] column, float defaultValue = 0.0) {
    int field = DbFieldNum(results, column);
    if (field == -1) {
        return defaultValue;
    }
    return results.FetchFloat(field);
}

void DbFetchString(DBResultSet results, const char[] column, char[] buffer, int maxlen) {
    int field = DbFieldNum(results, column);
    if (field == -1) {
        buffer[0] = '\0';
        return;
    }
    results.FetchString(field, buffer, maxlen);
}

void ApplyLoadoutFromDbRow(int client, DBResultSet results) {
    char knifeClass[64];
    knifeClass[0] = '\0';

    int knifeIdx = DbFetchInt(results, "knife", -1);
    if (knifeIdx >= 0) {
        KnifeClassFromIndex(knifeIdx, knifeClass, sizeof(knifeClass));
    }

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        char column[32];
        strcopy(column, sizeof(column), g_ClutchDbColumns[i]);

        int paintkit = DbFetchInt(results, column, 0);
        if (paintkit <= 0) {
            continue;
        }

        char floatCol[40];
        Format(floatCol, sizeof(floatCol), "%s_float", column);
        float wear = DbFetchFloat(results, floatCol, 0.0);
        if (wear <= 0.0) {
            wear = 0.15;
        }

        char seedCol[40];
        Format(seedCol, sizeof(seedCol), "%s_seed", column);
        int seed = DbFetchInt(results, seedCol, 0);

        char trakCol[40];
        Format(trakCol, sizeof(trakCol), "%s_trak", column);
        int stattrak = DbFetchInt(results, trakCol, 0);

        char tagCol[40];
        Format(tagCol, sizeof(tagCol), "%s_tag", column);
        char nametag[64];
        DbFetchString(results, tagCol, nametag, sizeof(nametag));

        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);
        bool isMelee = IsMeleeWeaponKey(weaponKey);

        if (isMelee && knifeClass[0] == '\0') {
            strcopy(knifeClass, sizeof(knifeClass), weaponKey);
        }

        int weapon = FindPlayerWeapon(client, weaponKey);
        if (weapon != -1) {
            SetClutchWeaponProps(client, weapon, paintkit, wear, seed, stattrak, nametag, isMelee);
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
    }

    if (knifeClass[0] != '\0') {
        ClutchSetClientKnife(client, knifeClass);
    }

    CS_UpdateClientModel(client);
}

public void ApplyClientSkinsFrame(any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0) {
        ApplyClientSkins(client);
    }
}

void ApplyClientSkins(int client) {
    if (!IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        return;
    }

    QueryPlayerLoadout(client, steamId, 0);
}
