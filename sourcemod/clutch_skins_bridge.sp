#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#undef REQUIRE_PLUGIN
#tryinclude <weapons>
#include <sdkhooks>
#include <PTaH>

#if defined _weapons_included_
    bool g_bWeaponsReloadNative = false;
    bool g_bLoggedMissingReloadNative = false;
#endif

#define PLUGIN_VERSION "3.5.2"
#define GLOVE_THINK_TICK_MOD 8
#define APPLY_COOLDOWN_SECONDS 3.0
#define CLUTCH_WEAPON_SLOTS 53
#define CLUTCH_KNIFE_CLASS_LEN 64
#define ENTITY_APPLY_COOLDOWN 1.5
#define REAPPLY_PASS_COUNT 6
#define SPAWN_APPLY_AFTER_GLOVES_DELAY 1.25
#define SPAWN_GLOVE_DB_REFRESH_DELAY 0.75
#define FORCE_WEAPONS_AFTER_GLOVES_DELAY 1.5

ConVar g_cvDebug;
ConVar g_cvWeaponsDb;
ConVar g_cvWeaponsTablePrefix;
ConVar g_cvRefreshSeconds;
ConVar g_cvGlovesWorldModel;

Database g_hWeaponsDb = null;
char g_sTablePrefix[16];
bool g_bLoggedMissingLoadout[MAXPLAYERS + 1];
float g_fLastApplyTime[MAXPLAYERS + 1];
int g_iLastKnifePaint[MAXPLAYERS + 1];
int g_iItemIdHigh = 16384;
bool g_bGlovesTableReady = false;
bool g_bGlovesPending[MAXPLAYERS + 1];
int g_iGloveQueryGen[MAXPLAYERS + 1];
int g_iGloveApplyGen[MAXPLAYERS + 1];
bool g_bForceGloveApply[MAXPLAYERS + 1];
int g_iLastGloveGroup[MAXPLAYERS + 1];
int g_iLastGlovePaint[MAXPLAYERS + 1];
bool g_bGloveThinkHooked[MAXPLAYERS + 1];
int g_iTeamGloveGroup[MAXPLAYERS + 1][2];
int g_iTeamGlovePaint[MAXPLAYERS + 1][2];
float g_fTeamGloveWear[MAXPLAYERS + 1][2];
Handle g_hRefreshTimer = null;

int g_CachedPaintkit[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
float g_CachedWear[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedSeed[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedTrak[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedTrakCount[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
char g_CachedTag[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS][64];
int g_iAppliedPaintkit[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
char g_CachedKnifeClass[MAXPLAYERS + 1][CLUTCH_KNIFE_CLASS_LEN];
float g_fLastEntityApply[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
float g_fReapplyDelays[REAPPLY_PASS_COUNT] = {0.0, 0.15, 0.35, 0.75, 1.5, 3.0};

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
    g_cvGlovesWorldModel = CreateConVar(
        "clutch_skins_gloves_world_model",
        "0",
        "0 = glove skin in your view only (m_nBody=1, no m_hMoveParent). 1 = others also see gloves on your player model",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    AutoExecConfig(true, "clutch_skins_bridge");

    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));

    RegAdminCmd("sm_reloadclutchskins", Command_ReloadSkins, ADMFLAG_ROOT, "Re-apply clutch skins from weapons DB");
    RegAdminCmd("sm_clutch_applyskins", Command_ApplySkins, ADMFLAG_ROOT, "Re-apply clutch skins to all players");

    ConnectWeaponsDatabase();

    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_Post);

    PTaH(PTaH_GiveNamedItemPost, Hook, Clutch_GiveNamedItemPost);

#if defined _weapons_included_
    MarkNativeAsOptional("Weapons_ReloadClientData");
#endif

    UpdateRefreshTimer();
}

public void OnLibraryAdded(const char[] name) {
#if defined _weapons_included_
    if (StrEqual(name, "weapons")) {
        RefreshWeaponsReloadNativeFlag();
    }
#endif
}

public void OnLibraryRemoved(const char[] name) {
#if defined _weapons_included_
    if (StrEqual(name, "weapons")) {
        g_bWeaponsReloadNative = false;
    }
#endif
}

public void OnConfigsExecuted() {
    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));
    UpdateRefreshTimer();
}

void UpdateRefreshTimer() {
    if (g_hRefreshTimer != null) {
        KillTimer(g_hRefreshTimer);
        g_hRefreshTimer = null;
    }

    float refresh = g_cvRefreshSeconds.FloatValue;
    if (refresh > 0.0) {
        g_hRefreshTimer = CreateTimer(refresh, Timer_RefreshFromDb, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnAllPluginsLoaded() {
    if (!LibraryExists("weapons")) {
        LogMessage("[Clutch] weapons.smx not loaded — knife models need kgns Weapons & Knives + PTaH");
    }
    ClutchWarnIfKgnsGlovesLoaded();
#if defined _weapons_included_
    RefreshWeaponsReloadNativeFlag();
#endif
}

bool ClutchIsKgnsGlovesPluginRunning() {
    char name[64];
    Handle iter = GetPluginIterator();
    while (MorePlugins(iter)) {
        Handle plugin = ReadPlugin(iter);
        if (GetPluginStatus(plugin) != Plugin_Running) {
            continue;
        }
        GetPluginInfo(plugin, PlInfo_Name, name, sizeof(name));
        if (StrEqual(name, "Gloves", false)) {
            delete iter;
            return true;
        }
    }
    delete iter;
    return false;
}

void ClutchWarnIfKgnsGlovesLoaded() {
    if (!ClutchIsKgnsGlovesPluginRunning()) {
        return;
    }
    LogError(
        "[Clutch] kgns gloves.smx is loaded — it applies gloves on spawn from the same SQLite table as this bridge, which causes DOUBLE gloves. Move it to addons/sourcemod/plugins/disabled/gloves.smx and sm plugins reload"
    );
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
    g_bGlovesTableReady = false;
    EnsureGlovesTable();

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Connected to weapons database (v%s)", PLUGIN_VERSION);
    }
}

void EnsureGlovesTable() {
    if (g_hWeaponsDb == null) {
        return;
    }

    char query[512];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %sgloves (steamid varchar(32) NOT NULL PRIMARY KEY, t_group int(5) NOT NULL DEFAULT 0, t_glove int(5) NOT NULL DEFAULT 0, t_float decimal(3,2) NOT NULL DEFAULT 0.0, ct_group int(5) NOT NULL DEFAULT 0, ct_glove int(5) NOT NULL DEFAULT 0, ct_float decimal(3,2) NOT NULL DEFAULT 0.0)",
        g_sTablePrefix
    );
    g_hWeaponsDb.Query(T_EnsureGlovesTableCallback, query, _, DBPrio_High);
}

public void T_EnsureGlovesTableCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[Clutch] gloves table create failed: %s", error);
        return;
    }
    g_bGlovesTableReady = true;
}

public Action Timer_RefreshFromDb(Handle timer) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client)) {
            ApplyClientSkins(client, false);
        }
    }
    return Plugin_Continue;
}

public Action Command_ReloadSkins(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            ClutchBeginForcedSync(i);
        }
    }
    ReplyToCommand(client, "[Clutch] Loadouts reaplicados do weapons DB.");
    return Plugin_Handled;
}

public Action Command_ApplySkins(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            ClutchBeginForcedSync(i);
        }
    }
    ReplyToCommand(client, "[Clutch] Reaplicando skins nos jogadores.");
    return Plugin_Handled;
}

void ClutchBeginForcedSync(int client) {
    g_bForceGloveApply[client] = true;
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client]++;
    g_iGloveApplyGen[client]++;

    char steamId[32];
    if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        QueryPlayerGloves(client, steamId, 0);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(FORCE_WEAPONS_AFTER_GLOVES_DELAY, Timer_ApplyWeaponsAfterGloves, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplyWeaponsAfterGloves(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
        ApplyClientSkins(client, true);
    }
    return Plugin_Stop;
}

public void OnClientDisconnect(int client) {
    if (!IsFakeClient(client)) {
        SDKUnhook(client, SDKHook_WeaponEquip, OnWeaponEquip);
    }
    g_bLoggedMissingLoadout[client] = false;
    g_fLastApplyTime[client] = 0.0;
    g_iLastKnifePaint[client] = 0;
    g_iLastGloveGroup[client] = 0;
    g_iLastGlovePaint[client] = 0;
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client] = 0;
    g_iGloveApplyGen[client] = 0;
    g_bForceGloveApply[client] = false;
    g_CachedKnifeClass[client][0] = '\0';
    ClutchDisableGloveThink(client);
    g_iTeamGloveGroup[client][0] = 0;
    g_iTeamGloveGroup[client][1] = 0;
    g_iTeamGlovePaint[client][0] = 0;
    g_iTeamGlovePaint[client][1] = 0;
    g_fTeamGloveWear[client][0] = 0.15;
    g_fTeamGloveWear[client][1] = 0.15;

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        g_CachedPaintkit[client][i] = 0;
        g_iAppliedPaintkit[client][i] = 0;
        g_fLastEntityApply[client][i] = 0.0;
        g_CachedTag[client][i][0] = '\0';
    }
}

public void OnClientPutInServer(int client) {
    if (IsFakeClient(client)) {
        return;
    }
    SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
    ScheduleApplyClientSkins(client);
    if (IsPlayerAlive(client)) {
        ScheduleQueryPlayerGloves(client);
    }
}

public Action OnWeaponEquip(int client, int weapon) {
    if (client <= 0 || IsFakeClient(client) || !IsValidEntity(weapon)) {
        return Plugin_Continue;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    int idx = GetClutchIndexForClassname(client, classname);
    if (idx < 0 || g_CachedPaintkit[client][idx] <= 0) {
        return Plugin_Continue;
    }

    bool isKnife = IsMeleeClassname(classname);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(weapon);
    pack.WriteCell(idx);
    pack.WriteCell(isKnife ? 1 : 0);
    CreateTimer(0.1, Timer_ApplyEquippedWeapon, pack, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_ApplyEquippedWeapon(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    int weapon = pack.ReadCell();
    int idx = pack.ReadCell();
    bool isKnife = pack.ReadCell() == 1;
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsValidEntity(weapon)) {
        return Plugin_Stop;
    }

    ApplyCachedSkinToEntity(client, weapon, idx, isKnife, true);
    return Plugin_Stop;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client]++;
    g_iLastGloveGroup[client] = 0;
    g_iLastGlovePaint[client] = 0;

    ClutchStripMismatchedSpawnWearable(client);

    int userid = GetClientUserId(client);
    CreateTimer(0.05, Timer_ApplySpawnGlovesFromCache, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(SPAWN_GLOVE_DB_REFRESH_DELAY, Timer_QueryPlayerGlovesDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(SPAWN_APPLY_AFTER_GLOVES_DELAY, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
}

void ClutchStripMismatchedSpawnWearable(int client) {
    int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (ent == -1 || !IsValidEntity(ent)) {
        return;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        ClutchDestroyWearableEntity(ent);
        SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
        return;
    }

    int idx = team == CS_TEAM_CT ? 1 : 0;
    int wantGroup = g_iTeamGloveGroup[client][idx];
    int wantPaint = g_iTeamGlovePaint[client][idx];
    if (wantGroup <= 0 || wantPaint <= 0) {
        ClutchDestroyWearableEntity(ent);
        SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
        SetEntProp(client, Prop_Send, "m_nBody", 0);
        return;
    }

    int def = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");
    int paint = GetEntProp(ent, Prop_Send, "m_nFallbackPaintKit");
    if (def != wantGroup || paint != wantPaint) {
        ClutchDestroyWearableEntity(ent);
        SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
        SetEntProp(client, Prop_Send, "m_nBody", 0);
    }
}

public Action Timer_ApplySpawnGlovesFromCache(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) {
        return Plugin_Stop;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        return Plugin_Stop;
    }

    int idx = team == CS_TEAM_CT ? 1 : 0;
    int group = g_iTeamGloveGroup[client][idx];
    int paint = g_iTeamGlovePaint[client][idx];
    float wear = g_fTeamGloveWear[client][idx];
    if (group <= 0 || paint <= 0) {
        return Plugin_Stop;
    }

    g_bForceGloveApply[client] = true;
    ClutchGivePlayerGloves(client, group, paint, wear);
    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Spawn cache gloves %d/%d for %N before weapons", group, paint, client);
    }
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    CreateTimer(3.0, Timer_ApplyAllPlayersSkins, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void Clutch_GiveNamedItemPost(
    int client,
    const char[] classname,
    const CEconItemView item,
    int entity,
    bool originIsNull,
    const float origin[3]
) {
    if (client <= 0 || IsFakeClient(client) || entity <= 0) {
        return;
    }

    char cn[64];
    GetEntityClassname(entity, cn, sizeof(cn));
    int idx = GetClutchIndexForClassname(client, cn);
    if (idx == -1) {
        return;
    }

    int paintkit = g_CachedPaintkit[client][idx];
    if (paintkit <= 0) {
        return;
    }

    int entityPaint = GetEntProp(entity, Prop_Send, "m_nFallbackPaintKit");
    if (entityPaint == paintkit) {
        g_iAppliedPaintkit[client][idx] = paintkit;
        return;
    }

    ApplyCachedSkinToEntity(client, entity, idx, IsMeleeClassname(cn), true);
    if (IsMeleeClassname(cn) && g_iLastGloveGroup[client] > 0) {
        ClutchEnforceGloveState(client);
    }
}

public Action Timer_ApplyCachedEntity(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    int entity = pack.ReadCell();
    int idx = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsValidEntity(entity)) {
        return Plugin_Stop;
    }

    if (idx < 0 || idx >= CLUTCH_WEAPON_SLOTS) {
        return Plugin_Stop;
    }

    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    bool isKnife = IsMeleeClassname(classname);

    ApplyCachedSkinToEntity(client, entity, idx, isKnife, false);
    return Plugin_Stop;
}

int GetClutchIndexForClassname(int client, const char[] classname) {
    bool melee = IsMeleeClassname(classname);

    if (melee && client > 0 && g_CachedKnifeClass[client][0] != '\0') {
        for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
            if (StrEqual(g_ClutchWeaponKeys[i], g_CachedKnifeClass[client], false)) {
                return i;
            }
        }
    }

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        if (melee) {
            if (IsMeleeWeaponKey(g_ClutchWeaponKeys[i])) {
                return i;
            }
        } else if (StrEqual(classname, g_ClutchWeaponKeys[i], false)) {
            return i;
        }
    }
    return -1;
}

void UpdateSlotCache(
    int client,
    int idx,
    int paintkit,
    float wear,
    int seed,
    int trak,
    int trakCount,
    const char[] tag
) {
    g_CachedPaintkit[client][idx] = paintkit;
    g_CachedWear[client][idx] = wear;
    g_CachedSeed[client][idx] = seed;
    g_CachedTrak[client][idx] = trak;
    g_CachedTrakCount[client][idx] = trakCount;
    strcopy(g_CachedTag[client][idx], sizeof(g_CachedTag[][]), tag);
}

void ClearSlotCache(int client, int idx) {
    g_CachedPaintkit[client][idx] = 0;
    g_iAppliedPaintkit[client][idx] = 0;
    g_CachedWear[client][idx] = 0.0;
    g_CachedSeed[client][idx] = 0;
    g_CachedTrak[client][idx] = 0;
    g_CachedTrakCount[client][idx] = 0;
    g_CachedTag[client][idx][0] = '\0';
    g_fLastEntityApply[client][idx] = 0.0;
}

void ClearAllMeleeSlotCaches(int client) {
    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        if (IsMeleeWeaponKey(g_ClutchWeaponKeys[i])) {
            ClearSlotCache(client, i);
        }
    }
    g_CachedKnifeClass[client][0] = '\0';
    g_iLastKnifePaint[client] = 0;
}

bool ApplyCachedSkinToEntity(int client, int entity, int idx, bool isKnife, bool force = false) {
    int paintkit = g_CachedPaintkit[client][idx];
    if (paintkit <= 0 || !IsPaintableWeaponEntity(entity)) {
        return false;
    }

    int entityPaint = GetEntProp(entity, Prop_Send, "m_nFallbackPaintKit");
    if (!force
        && g_iAppliedPaintkit[client][idx] == paintkit
        && entityPaint == paintkit) {
        return false;
    }

    float now = GetGameTime();
    if (!force
        && now - g_fLastEntityApply[client][idx] < ENTITY_APPLY_COOLDOWN
        && g_iAppliedPaintkit[client][idx] == paintkit) {
        return false;
    }
    g_fLastEntityApply[client][idx] = now;

    SetClutchWeaponProps(
        client,
        entity,
        paintkit,
        g_CachedWear[client][idx],
        g_CachedSeed[client][idx],
        g_CachedTrak[client][idx],
        g_CachedTrakCount[client][idx],
        g_CachedTag[client][idx],
        isKnife
    );
    g_iAppliedPaintkit[client][idx] = paintkit;

    if (g_cvDebug.BoolValue) {
        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));
        LogMessage("[Clutch] Applied cached paintkit %d on %s for %N", paintkit, classname, client);
    }

    if (isKnife && ClutchClientHasGlovesLoaded(client)) {
        ClutchEnforceGloveState(client);
    } else if (isKnife) {
        ClutchRequestClientModelUpdate(client);
    }

    return true;
}

public Action Timer_ApplyAllPlayersSkins(Handle timer) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client)) {
            ApplyClientSkins(client, false);
        }
    }
    return Plugin_Stop;
}

void ScheduleApplyClientSkins(int client) {
    int userid = GetClientUserId(client);
    CreateTimer(SPAWN_APPLY_AFTER_GLOVES_DELAY, Timer_ApplySkinsDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplySkinsDelayed(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0) {
        ApplyClientSkins(client, false);
    }
    return Plugin_Stop;
}

void ClutchPersistGloveLoadout(int client, int team, int group, int paint, float wear) {
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        return;
    }

    int idx = team == CS_TEAM_CT ? 1 : 0;
    g_iTeamGloveGroup[client][idx] = group;
    g_iTeamGlovePaint[client][idx] = paint;
    g_fTeamGloveWear[client][idx] = wear;

    if (group > 0 && paint > 0) {
        int other = idx == 0 ? 1 : 0;
        g_iTeamGloveGroup[client][other] = group;
        g_iTeamGlovePaint[client][other] = paint;
        g_fTeamGloveWear[client][other] = wear;
    }
}

void ForceReapplyPlayerGloves(int client) {
    g_bForceGloveApply[client] = true;
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client]++;
    g_iGloveApplyGen[client]++;

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        g_bForceGloveApply[client] = false;
        return;
    }
    QueryPlayerGloves(client, steamId, 0);
}

void ScheduleGloveViewMaintain(int client, float delay) {
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(delay, Timer_MaintainGloveView, pack, TIMER_FLAG_NO_MAPCHANGE);
}

void ScheduleQueryPlayerGloves(int client) {
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }
    int userid = GetClientUserId(client);
    CreateTimer(SPAWN_GLOVE_DB_REFRESH_DELAY, Timer_QueryPlayerGlovesDelayed, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_QueryPlayerGlovesDelayed(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Stop;
    }

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        return Plugin_Stop;
    }

    QueryPlayerGloves(client, steamId, 0);
    return Plugin_Stop;
}

public Action Timer_ApplyKnifeSkinDelayed(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    char knifeClass[64];
    pack.ReadString(knifeClass, sizeof(knifeClass));
    int paintkit = pack.ReadCell();
    float wear = pack.ReadFloat();
    int seed = pack.ReadCell();
    int stattrak = pack.ReadCell();
    int stattrakCount = pack.ReadCell();
    char nametag[64];
    pack.ReadString(nametag, sizeof(nametag));
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    int weapon = FindPlayerWeapon(client, knifeClass);
    if (weapon != -1) {
        SetClutchWeaponProps(client, weapon, paintkit, wear, seed, stattrak, stattrakCount, nametag, true);
        if (g_cvDebug.BoolValue) {
            LogMessage(
                "[Clutch] Applied %s paintkit %d (knife delayed) for %N",
                knifeClass,
                paintkit,
                client
            );
        }
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

int FindPlayerWeaponInSlots(int client, const char[] weaponKey, bool matchMelee) {
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

int FindPlayerWeapon(int client, const char[] weaponKey) {
    bool matchMelee = IsMeleeWeaponKey(weaponKey);

    int weapon = FindPlayerWeaponInSlots(client, weaponKey, matchMelee);
    if (weapon != -1) {
        return weapon;
    }

    int offset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
    if (offset == -1) {
        return -1;
    }

    for (int i = 0; i < 64; i++) {
        weapon = GetEntDataEnt2(client, offset + (i * 4));
        if (!IsPaintableWeaponEntity(weapon)) {
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
    int stattrakFlag,
    int stattrakCount,
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
        if (stattrakFlag > 0) {
            int count = stattrakCount > 0 ? stattrakCount : 1;
            SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", count);
        } else {
            SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", -1);
        }
    } else if (stattrakFlag > 0) {
        int count = stattrakCount > 0 ? stattrakCount : 1;
        SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", count);
        SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 9);
    } else {
        SetEntProp(weapon, Prop_Send, "m_nFallbackStatTrak", -1);
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

    if (HasEntProp(weapon, Prop_Send, "m_bInitialized")) {
        SetEntProp(weapon, Prop_Send, "m_bInitialized", 1);
    }

    ClutchNetworkUpdate(weapon);
    if (isKnife && ClutchClientHasGlovesLoaded(client)) {
        ClutchEnforceGloveState(client);
    } else if (isKnife) {
        ClutchRequestClientModelUpdate(client);
    }
}

void ClutchNetworkUpdate(int entity) {
    int offset = FindSendPropInfo("CBaseEntity", "m_nModelIndex");
    if (offset != -1) {
        ChangeEdictState(entity, offset);
    }
}

#if defined _weapons_included_
void RefreshWeaponsReloadNativeFlag() {
    g_bWeaponsReloadNative = LibraryExists("weapons")
        && GetFeatureStatus(FeatureType_Native, "Weapons_ReloadClientData") == FeatureStatus_Available;

    if (LibraryExists("weapons") && !g_bWeaponsReloadNative && !g_bLoggedMissingReloadNative) {
        g_bLoggedMissingReloadNative = true;
        LogMessage(
            "[Clutch] weapons.smx has no Weapons_ReloadClientData native — paint may stay stale. Run: bash scripts/patch-weapons-reload-native.sh"
        );
    }
}

void TryReloadWeaponsPluginData(int client) {
    if (!LibraryExists("weapons") || !g_bWeaponsReloadNative) {
        return;
    }
    Weapons_ReloadClientData(client);
}
#endif

void ApplyAllCachedWeaponsToClient(int client, bool force) {
    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        int paintkit = g_CachedPaintkit[client][i];
        if (paintkit <= 0) {
            continue;
        }

        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);

        if (IsMeleeWeaponKey(weaponKey)) {
            if (g_CachedKnifeClass[client][0] == '\0') {
                continue;
            }
            if (!StrEqual(weaponKey, g_CachedKnifeClass[client], false)) {
                continue;
            }
        }

        int weapon = FindPlayerWeapon(client, weaponKey);
        if (weapon == -1) {
            continue;
        }

        ApplyCachedSkinToEntity(client, weapon, i, IsMeleeWeaponKey(weaponKey), force);
    }

    if (ClutchClientHasGlovesLoaded(client)) {
        ClutchEnforceGloveState(client);
    } else {
        CS_UpdateClientModel(client);
    }
}

void ScheduleForceReapply(int client, bool force) {
    if (!IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    if (force && ClutchClientHasGlovesLoaded(client)) {
        if (g_cvDebug.BoolValue) {
            LogMessage(
                "[Clutch] Skipping knife force-reapply passes (gloves active) for %N",
                client
            );
        }
        return;
    }

    int userid = GetClientUserId(client);
    for (int i = 0; i < REAPPLY_PASS_COUNT; i++) {
        DataPack pack = new DataPack();
        pack.WriteCell(userid);
        pack.WriteCell(force ? 1 : 0);
        pack.WriteCell(i);
        CreateTimer(g_fReapplyDelays[i], Timer_ForceReapplyPass, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ForceReapplyPass(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    bool force = pack.ReadCell() == 1;
    int pass = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    ApplyAllCachedWeaponsToClient(client, force);

    if (force && pass == REAPPLY_PASS_COUNT - 1 && g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Finished forced re-apply passes for %N", client);
    }

    return Plugin_Stop;
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

void QueryPlayerLoadout(int client, const char[] steamId, int altAttempt, bool force = false) {
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
    pack.WriteCell(force ? 1 : 0);

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
    bool force = pack.ReadCell() == 1;
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
            QueryPlayerLoadout(client, steamId, 1, force);
            return;
        }

        if (!g_bLoggedMissingLoadout[client]) {
            LogMessage("[Clutch] Sem loadout no DB para %s (%N)", steamId, client);
            g_bLoggedMissingLoadout[client] = true;
        }
        return;
    }

    g_bLoggedMissingLoadout[client] = false;
#if defined _weapons_included_
    if (!force && !ClutchClientHasGlovesLoaded(client)) {
        TryReloadWeaponsPluginData(client);
    }
#endif
    ApplyLoadoutFromDbRow(client, results, force);
}

void QueryPlayerGloves(int client, const char[] steamId, int altAttempt) {
    if (g_hWeaponsDb == null) {
        return;
    }

    if (!g_bGlovesTableReady) {
        EnsureGlovesTable();
    }

    g_bGlovesPending[client] = true;
    g_iGloveQueryGen[client]++;
    g_iGloveApplyGen[client]++;
    int queryGen = g_iGloveQueryGen[client];

    char escaped[64];
    g_hWeaponsDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);
    pack.WriteCell(queryGen);

    char query[256];
    Format(
        query,
        sizeof(query),
        "SELECT * FROM %sgloves WHERE steamid='%s' LIMIT 1",
        g_sTablePrefix,
        escaped
    );
    g_hWeaponsDb.Query(T_ApplyGlovesFromDbCallback, query, pack);
}

public void T_ApplyGlovesFromDbCallback(Database database, DBResultSet results, const char[] error, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int altAttempt = pack.ReadCell();
    int queryGen = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return;
    }

    if (queryGen != g_iGloveQueryGen[client]) {
        return;
    }

    if (results == null) {
        if (g_cvDebug.BoolValue) {
            LogError("[Clutch] gloves DB query failed: %s", error);
        }
        g_bGlovesPending[client] = false;
        return;
    }

    if (!results.FetchRow()) {
        if (altAttempt == 0) {
            if (steamId[6] == '1') {
                steamId[6] = '0';
            } else if (steamId[6] == '0') {
                steamId[6] = '1';
            }
            QueryPlayerGloves(client, steamId, 1);
        } else {
            ClutchGivePlayerGloves(client, 0, 0, 0.0);
        }
        return;
    }

    ApplyGlovesFromDbRow(client, results);
}

bool ClutchShouldUpdateClientModel(int client) {
    if (g_bGlovesPending[client]) {
        return false;
    }
    if (g_iLastGloveGroup[client] > 0 && g_iLastGlovePaint[client] > 0) {
        return false;
    }
    return true;
}

bool ClutchClientHasGlovesLoaded(int client) {
    if (g_iLastGloveGroup[client] > 0 && g_iLastGlovePaint[client] > 0) {
        return true;
    }
    return g_iTeamGloveGroup[client][0] > 0 || g_iTeamGloveGroup[client][1] > 0;
}

void ClutchRequestClientModelUpdate(int client) {
    if (!ClutchShouldUpdateClientModel(client)) {
        ClutchEnforceGloveState(client);
        return;
    }
    CS_UpdateClientModel(client);
}

void ClutchEnableGloveThink(int client) {
    if (client <= 0 || IsFakeClient(client) || g_bGloveThinkHooked[client]) {
        return;
    }
    SDKHook(client, SDKHook_PreThink, OnGlovePreThink);
    g_bGloveThinkHooked[client] = true;
}

void ClutchDisableGloveThink(int client) {
    if (client <= 0 || !g_bGloveThinkHooked[client]) {
        return;
    }
    SDKUnhook(client, SDKHook_PreThink, OnGlovePreThink);
    g_bGloveThinkHooked[client] = false;
}

public void OnGlovePreThink(int client) {
    if (!IsPlayerAlive(client) || g_iLastGloveGroup[client] <= 0) {
        return;
    }
    if ((GetGameTickCount() % GLOVE_THINK_TICK_MOD) != (client % GLOVE_THINK_TICK_MOD)) {
        return;
    }
    ClutchEnforceGloveState(client);
}

void ClutchEnforceGloveState(int client) {
    if (g_iLastGloveGroup[client] <= 0 || g_iLastGlovePaint[client] <= 0) {
        return;
    }

    int wearable = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (wearable == -1 || !IsValidEntity(wearable)) {
        return;
    }

    // PTaH / knife plugins re-set m_szArmsModel after gloves — that draws default glove mesh under the skin.
    ClutchFixCustomArms(client);
    ClutchScrubStrayWearables(client, wearable);

    // m_nBody=1 hides the default glove bodygroup; wearable supplies the paintkit (view always).
    SetEntProp(client, Prop_Send, "m_nBody", 1);
    ClutchNetworkUpdate(wearable);
}

void ClutchDestroyWearableEntity(int entity) {
    if (entity == -1 || !IsValidEntity(entity)) {
        return;
    }

    if (HasEntProp(entity, Prop_Data, "m_hOwnerEntity")) {
        SetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity", -1);
    }
    if (HasEntProp(entity, Prop_Data, "m_hParent")) {
        SetEntPropEnt(entity, Prop_Data, "m_hParent", -1);
    }
    if (HasEntProp(entity, Prop_Data, "m_hMoveParent")) {
        SetEntPropEnt(entity, Prop_Data, "m_hMoveParent", -1);
    }

    AcceptEntityInput(entity, "KillHierarchy");
    if (IsValidEntity(entity)) {
        RemoveEntity(entity);
    }
}

void ClutchScrubStrayWearables(int client, int keepEnt) {
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "wearable_item")) != -1) {
        if (!IsValidEntity(entity) || entity == keepEnt) {
            continue;
        }

        if (
            GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") == client
            || GetEntPropEnt(entity, Prop_Data, "m_hParent") == client
            || GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") == client
        ) {
            ClutchDestroyWearableEntity(entity);
        }
    }
}

void ClutchCullEngineDefaultWearable(int client) {
    int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (ent == -1 || !IsValidEntity(ent)) {
        ClutchScrubStrayWearables(client, -1);
        return;
    }

    if (g_iLastGloveGroup[client] > 0) {
        int defIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");
        int paintkit = GetEntProp(ent, Prop_Send, "m_nFallbackPaintKit");
        if (defIndex == g_iLastGloveGroup[client] && paintkit == g_iLastGlovePaint[client]) {
            return;
        }
    }

    ClutchDestroyWearableEntity(ent);
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
    SetEntProp(client, Prop_Send, "m_nBody", 0);
    ClutchScrubStrayWearables(client, -1);
}

void ClutchFixCustomArms(int client) {
    char armsModel[2];
    GetEntPropString(client, Prop_Send, "m_szArmsModel", armsModel, sizeof(armsModel));
    if (armsModel[0]) {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", "");
    }
}

void ClutchClearWearableGloves(int client) {
    ClutchDisableGloveThink(client);
    int wearable = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    int guard = 0;
    while (wearable != -1 && IsValidEntity(wearable) && guard < 64) {
        ClutchDestroyWearableEntity(wearable);
        wearable = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
        guard++;
    }
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);

    // Belt-and-suspenders: any wearable_item still parented to this client.
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "wearable_item")) != -1) {
        if (!IsValidEntity(entity)) {
            continue;
        }
        if (
            GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") == client ||
            GetEntPropEnt(entity, Prop_Data, "m_hParent") == client ||
            GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") == client
        ) {
            ClutchDestroyWearableEntity(entity);
        }
    }

    SetEntProp(client, Prop_Send, "m_nBody", 0);
    g_iLastGloveGroup[client] = 0;
    g_iLastGlovePaint[client] = 0;
}

bool ClutchHasExtraWearables(int client) {
    int count = 0;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "wearable_item")) != -1) {
        if (!IsValidEntity(entity)) {
            continue;
        }
        if (GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") == client) {
            count++;
            if (count > 1) {
                return true;
            }
        }
    }
    return false;
}

bool ClutchShouldSkipGloveReapply(int client, int group, int paintkit) {
    if (g_bForceGloveApply[client]) {
        return false;
    }
    if (g_iLastGloveGroup[client] != group || g_iLastGlovePaint[client] != paintkit) {
        return false;
    }
    int wearable = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (wearable == -1 || !IsValidEntity(wearable)) {
        return false;
    }
    return !ClutchHasExtraWearables(client);
}

public void OnFrame_FixArmsAfterGloves(any userid) {
    // Do not clear m_szArmsModel here — it reverts glove view to default mesh.
}

public void OnFrame_FinalizeGloveBody(any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) {
        return;
    }
    ClutchEnforceGloveState(client);
}

void ClutchMaintainGloveView(int client) {
    ClutchEnforceGloveState(client);
}

void ClutchKillActiveWearable(int client) {
    int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (ent != -1 && IsValidEntity(ent)) {
        AcceptEntityInput(ent, "KillHierarchy");
    }
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);
}

public Action Timer_RetryGlovesAfterTeam(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client)) {
        char steamId[32];
        if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
            QueryPlayerGloves(client, steamId, 0);
        }
    }
    return Plugin_Stop;
}

void ClutchGivePlayerGloves(int client, int group, int paintkit, float wear) {
    if (group <= 0 || paintkit <= 0) {
        int clearTeam = GetClientTeam(client);
        ClutchPersistGloveLoadout(client, clearTeam, 0, 0, 0.0);
        ClutchFixCustomArms(client);
        ClutchClearWearableGloves(client);
        g_bGlovesPending[client] = false;
        g_bForceGloveApply[client] = false;
        return;
    }

    if (ClutchShouldSkipGloveReapply(client, group, paintkit)) {
        g_bGlovesPending[client] = false;
        g_bForceGloveApply[client] = false;
        ClutchEnableGloveThink(client);
        ClutchEnforceGloveState(client);
        if (g_cvDebug.BoolValue) {
            LogMessage(
                "[Clutch] Skipping glove reapply (already %d/%d) for %N",
                group,
                paintkit,
                client
            );
        }
        return;
    }

    ClutchKillActiveWearable(client);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(group);
    pack.WriteCell(paintkit);
    pack.WriteFloat(wear);
    pack.WriteCell(g_iGloveApplyGen[client]);
    CreateTimer(0.05, Timer_ApplyGlovesAfterClear, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplyGlovesAfterClear(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    int group = pack.ReadCell();
    int paintkit = pack.ReadCell();
    float wear = pack.ReadFloat();
    int applyGen = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    if (applyGen != g_iGloveApplyGen[client]) {
        if (g_cvDebug.BoolValue) {
            LogMessage("[Clutch] Stale glove apply timer ignored for userid %d", userid);
        }
        return Plugin_Stop;
    }

    if (!IsPlayerAlive(client)) {
        g_bGlovesPending[client] = false;
        g_bForceGloveApply[client] = false;
        return Plugin_Stop;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        g_bGlovesPending[client] = false;
        g_bForceGloveApply[client] = false;
        return Plugin_Stop;
    }

    if (group <= 0 || paintkit <= 0) {
        g_bGlovesPending[client] = false;
        return Plugin_Stop;
    }

    bool worldModel = g_cvGlovesWorldModel.BoolValue;

    // kgns gloves.smx flow: kill old wearable, clear conflicting arms model, spawn wearable.
    ClutchKillActiveWearable(client);
    ClutchFixCustomArms(client);

    int ent = CreateEntityByName("wearable_item");
    if (ent == -1) {
        g_bGlovesPending[client] = false;
        g_bForceGloveApply[client] = false;
        LogError("[Clutch] CreateEntityByName(wearable_item) failed for %N", client);
        return Plugin_Stop;
    }

    float appliedWear = wear;
    if (appliedWear <= 0.0) {
        appliedWear = 0.0001;
    } else if (appliedWear >= 1.0) {
        appliedWear = 0.999999;
    }

    SetEntProp(ent, Prop_Send, "m_iItemIDLow", -1);
    SetEntProp(ent, Prop_Send, "m_iItemIDHigh", -1);
    SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", group);
    SetEntProp(ent, Prop_Send, "m_nFallbackPaintKit", paintkit);
    SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", appliedWear);
    SetEntProp(ent, Prop_Send, "m_nFallbackSeed", GetRandomInt(1, 1000));
    SetEntProp(ent, Prop_Send, "m_iEntityQuality", 3);
    SetEntProp(ent, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
    SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", client);
    SetEntPropEnt(ent, Prop_Data, "m_hParent", client);
    if (worldModel) {
        SetEntPropEnt(ent, Prop_Data, "m_hMoveParent", client);
    }
    SetEntProp(ent, Prop_Send, "m_bInitialized", 1);

    DispatchSpawn(ent);

    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", ent);
    SetEntProp(client, Prop_Send, "m_nBody", 1);

    ClutchScrubStrayWearables(client, ent);
    ClutchNetworkUpdate(ent);

    g_iLastGloveGroup[client] = group;
    g_iLastGlovePaint[client] = paintkit;
    g_bGlovesPending[client] = false;
    g_bForceGloveApply[client] = false;

    ClutchPersistGloveLoadout(client, team, group, paintkit, wear);

    ClutchEnableGloveThink(client);
    ClutchEnforceGloveState(client);

    RequestFrame(OnFrame_FinalizeGloveBody, GetClientUserId(client));

    ScheduleGloveViewMaintain(client, 0.25);
    ScheduleGloveViewMaintain(client, 0.75);
    ScheduleGloveViewMaintain(client, 2.0);

    LogMessage(
        "[Clutch] Applied gloves group %d paintkit %d for %N (world_model=%d body=1 no_cs_update)",
        group,
        paintkit,
        client,
        worldModel ? 1 : 0
    );
    return Plugin_Stop;
}

public Action Timer_MaintainGloveView(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client)) {
        ClutchMaintainGloveView(client);
    }
    return Plugin_Stop;
}

void ApplyGlovesFromDbRow(int client, DBResultSet results) {
    int team = GetClientTeam(client);
    int group = 0;
    int paintkit = 0;
    float wear = 0.15;

    if (team == CS_TEAM_T) {
        group = DbFetchInt(results, "t_group", 0);
        paintkit = DbFetchInt(results, "t_glove", 0);
        wear = DbFetchFloat(results, "t_float", 0.15);
    } else if (team == CS_TEAM_CT) {
        group = DbFetchInt(results, "ct_group", 0);
        paintkit = DbFetchInt(results, "ct_glove", 0);
        wear = DbFetchFloat(results, "ct_float", 0.15);
    } else {
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        CreateTimer(0.5, Timer_RetryGlovesAfterTeam, pack, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    ClutchGivePlayerGloves(client, group, paintkit, wear);
    if (group <= 0 || paintkit <= 0) {
        if (g_cvDebug.BoolValue) {
            LogMessage("[Clutch] DB gloves empty for %N (team %d)", client, team);
        }
    }
}

int DbFieldNum(DBResultSet results, const char[] column) {
    int field = -1;
    if (results.FieldNameToNum(column, field)) {
        return field;
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

void ApplyLoadoutFromDbRow(int client, DBResultSet results, bool force) {
    char knifeClass[64];
    knifeClass[0] = '\0';

    int knifeIdx = DbFetchInt(results, "knife", -1);
    if (knifeIdx >= 0) {
        KnifeClassFromIndex(knifeIdx, knifeClass, sizeof(knifeClass));
    }

    int knifePaintkit = 0;
    float knifeWear = 0.15;
    int knifeSeed = 0;
    int knifeTrak = 0;
    int knifeTrakCount = 0;
    char knifeTag[64];
    knifeTag[0] = '\0';

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);

        if (IsMeleeWeaponKey(weaponKey)) {
            if (knifeClass[0] != '\0' && !StrEqual(weaponKey, knifeClass, false)) {
                continue;
            }

            char column[32];
            strcopy(column, sizeof(column), g_ClutchDbColumns[i]);
            knifePaintkit = DbFetchInt(results, column, 0);

            char floatCol[40];
            Format(floatCol, sizeof(floatCol), "%s_float", column);
            knifeWear = DbFetchFloat(results, floatCol, 0.15);
            if (knifeWear <= 0.0) {
                knifeWear = 0.15;
            }

            char seedCol[40];
            Format(seedCol, sizeof(seedCol), "%s_seed", column);
            knifeSeed = DbFetchInt(results, seedCol, 0);

            char trakCol[40];
            Format(trakCol, sizeof(trakCol), "%s_trak", column);
            knifeTrak = DbFetchInt(results, trakCol, 0);

            char trakCountCol[48];
            Format(trakCountCol, sizeof(trakCountCol), "%s_trak_count", column);
            knifeTrakCount = DbFetchInt(results, trakCountCol, 0);

            char tagCol[40];
            Format(tagCol, sizeof(tagCol), "%s_tag", column);
            DbFetchString(results, tagCol, knifeTag, sizeof(knifeTag));
            continue;
        }

        char column[32];
        strcopy(column, sizeof(column), g_ClutchDbColumns[i]);

        int paintkit = DbFetchInt(results, column, 0);
        if (paintkit <= 0) {
            ClearSlotCache(client, i);
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

        char trakCountCol[48];
        Format(trakCountCol, sizeof(trakCountCol), "%s_trak_count", column);
        int stattrakCount = DbFetchInt(results, trakCountCol, 0);

        char tagCol[40];
        Format(tagCol, sizeof(tagCol), "%s_tag", column);
        char nametag[64];
        DbFetchString(results, tagCol, nametag, sizeof(nametag));

        UpdateSlotCache(client, i, paintkit, wear, seed, stattrak, stattrakCount, nametag);

        int weapon = FindPlayerWeapon(client, weaponKey);
        bool needsApply = force || g_iAppliedPaintkit[client][i] != paintkit;
        if (!needsApply && weapon != -1) {
            if (GetEntProp(weapon, Prop_Send, "m_nFallbackPaintKit") != paintkit) {
                needsApply = true;
            } else if (GetEntProp(weapon, Prop_Send, "m_nFallbackSeed") != seed) {
                needsApply = true;
            }
        }
        if (weapon != -1 && needsApply) {
            SetClutchWeaponProps(client, weapon, paintkit, wear, seed, stattrak, stattrakCount, nametag, false);
            g_iAppliedPaintkit[client][i] = paintkit;
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
        } else if (weapon == -1 && g_cvDebug.BoolValue && force) {
            LogMessage("[Clutch] Weapon not found for key %s (%N)", weaponKey, client);
        }
    }

    ScheduleForceReapply(client, force);

    if (knifePaintkit <= 0) {
        ClearAllMeleeSlotCaches(client);
        return;
    }

    if (knifeClass[0] == '\0') {
        return;
    }

    strcopy(g_CachedKnifeClass[client], CLUTCH_KNIFE_CLASS_LEN, knifeClass);

    for (int k = 0; k < CLUTCH_WEAPON_SLOTS; k++) {
        if (StrEqual(g_ClutchWeaponKeys[k], knifeClass, false)) {
            UpdateSlotCache(client, k, knifePaintkit, knifeWear, knifeSeed, knifeTrak, knifeTrakCount, knifeTag);
            break;
        }
    }

    if (!force && g_iLastKnifePaint[client] == knifePaintkit) {
        int knifeWeapon = FindPlayerWeapon(client, knifeClass);
        if (knifeWeapon != -1
            && GetEntProp(knifeWeapon, Prop_Send, "m_nFallbackPaintKit") == knifePaintkit
            && GetEntProp(knifeWeapon, Prop_Send, "m_nFallbackSeed") == knifeSeed) {
            return;
        }
    }
    g_iLastKnifePaint[client] = knifePaintkit;

    ClutchSetClientKnife(client, knifeClass);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(knifeClass);
    pack.WriteCell(knifePaintkit);
    pack.WriteFloat(knifeWear);
    pack.WriteCell(knifeSeed);
    pack.WriteCell(knifeTrak);
    pack.WriteCell(knifeTrakCount);
    pack.WriteString(knifeTag);
    CreateTimer(0.35, Timer_ApplyKnifeSkinDelayed, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public void ApplyClientSkinsFrame(any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0) {
        ApplyClientSkins(client, false);
    }
}

void ApplyClientSkins(int client, bool force) {
    if (!IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    float now = GetGameTime();
    if (!force && (now - g_fLastApplyTime[client]) < APPLY_COOLDOWN_SECONDS) {
        return;
    }
    g_fLastApplyTime[client] = now;

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true)) {
        return;
    }

    QueryPlayerLoadout(client, steamId, 0, force);
}
