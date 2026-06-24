#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clutch_steam>

#undef REQUIRE_PLUGIN
#tryinclude <weapons>
#tryinclude <clutch_gloves>
#include <sdkhooks>
#include <PTaH>

#if defined _weapons_included_
    bool g_bWeaponsReloadNative = false;
    bool g_bWeaponsRefreshNative = false;
    bool g_bLoggedMissingReloadNative = false;
    bool g_bLoggedMissingRefreshNative = false;
#endif
#if defined _clutch_gloves_included_
    bool g_bGlovesNativeReady = false;
    bool g_bLoggedGlovesNativeMissing = false;
#endif

#define PLUGIN_VERSION "3.8.18"
#define CLUTCH_SITE_STICKER_SLOTS 5
#define STICKER_REAPPLY_PASS_COUNT 3
#define GLOVE_THINK_TICK_MOD 8
#define APPLY_COOLDOWN_SECONDS 3.0
#define CLUTCH_WEAPON_SLOTS 53
#define CLUTCH_STICKER_SLOTS 6
#define CLUTCH_KNIFE_CLASS_LEN 64
#define ENTITY_APPLY_COOLDOWN 1.5
#define WEAPON_REGIVE_COOLDOWN 10.0
#define REAPPLY_PASS_COUNT 3
#define SPAWN_APPLY_AFTER_GLOVES_DELAY 1.25
#define SPAWN_GLOVE_DB_REFRESH_DELAY 0.75
#define FORCE_WEAPONS_AFTER_GLOVES_DELAY 1.0

ConVar g_cvDebug;
ConVar g_cvWeaponsDb;
ConVar g_cvWeaponsTablePrefix;
ConVar g_cvStickersDb;
ConVar g_cvStickersTablePrefix;
ConVar g_cvStickersDbPath;
ConVar g_cvRefreshSeconds;
ConVar g_cvGlovesWorldModel;
ConVar g_cvDeferLive;
ConVar g_cvOncePerMatch;

Database g_hWeaponsDb = null;
Database g_hStickersDb = null;
char g_sStickersTable[32];
char g_sLegacyStickersTable[32];
char g_sResolvedStickersDbPath[PLATFORM_MAX_PATH];
char g_sTablePrefix[16];
bool g_bLoggedMissingLoadout[MAXPLAYERS + 1];
float g_fLastApplyTime[MAXPLAYERS + 1];
int g_iLastKnifePaint[MAXPLAYERS + 1];
int g_iItemIdHigh = 16384;
bool g_bGlovesTableReady = false;
bool g_bStickersTableReady = false;
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
bool g_bPendingWebLoadout[MAXPLAYERS + 1];

int g_CachedPaintkit[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
float g_CachedWear[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedSeed[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedTrak[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_CachedTrakCount[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
char g_CachedTag[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS][64];
int g_iAppliedPaintkit[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_iStickerSlots[MAXPLAYERS + 1][2][CLUTCH_WEAPON_SLOTS][CLUTCH_STICKER_SLOTS];
float g_fStickerWears[MAXPLAYERS + 1][2][CLUTCH_WEAPON_SLOTS][CLUTCH_STICKER_SLOTS];
char g_CachedKnifeClass[MAXPLAYERS + 1][CLUTCH_KNIFE_CLASS_LEN];
float g_fLastEntityApply[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
float g_fLastWeaponRegive[MAXPLAYERS + 1][CLUTCH_WEAPON_SLOTS];
int g_iReapplyGen[MAXPLAYERS + 1];
bool g_bAllowWeaponRegive[MAXPLAYERS + 1];
bool g_bMatchLoadoutSynced[MAXPLAYERS + 1];
float g_fReapplyDelays[REAPPLY_PASS_COUNT] = {0.35, 1.0, 2.0};
float g_fStickerReapplyDelays[STICKER_REAPPLY_PASS_COUNT] = {0.15, 0.45, 0.9};

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

/** CS item definition index — matches site weapon-defindex (weaponstickers1.weaponindex). */
int g_ClutchWeaponDefIndex[CLUTCH_WEAPON_SLOTS] = {
    9, 7, 16, 60, 1, 61, 32, 4, 2, 36, 63, 3, 30, 64, 35, 25,
    27, 29, 14, 28, 34, 17, 33, 24, 19, 26, 10, 13, 40, 8, 39, 38,
    11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23,
    0, 0, 0, 0, 0
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
#if defined _weapons_included_
    MarkNativeAsOptional("Weapons_ReloadClientData");
    MarkNativeAsOptional("Weapons_RefreshWeapon");
#endif
#if defined _clutch_gloves_included_
    MarkNativeAsOptional("ClutchGloves_RefreshClient");
    MarkNativeAsOptional("ClutchGloves_ApplyClient");
    MarkNativeAsOptional("ClutchGloves_IsClientUsingGloves");
#endif
    MarkNativeAsOptional("PTaH_GetItemDefinitionByDefIndex");
    MarkNativeAsOptional("CEconItemView.AttributeList.get");
    return APLRes_Success;
}

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
    g_cvStickersDb = CreateConVar(
        "clutch_stickers_db",
        "csgo_weaponstickers",
        "Database connection for CSGO_WeaponStickers (databases.cfg)",
        FCVAR_NOTIFY
    );
    g_cvStickersTablePrefix = CreateConVar(
        "clutch_stickers_table_prefix",
        "",
        "Table prefix for weaponstickers plugin (weaponstickers1)",
        FCVAR_NOTIFY
    );
    g_cvStickersDbPath = CreateConVar(
        "clutch_stickers_db_path",
        "",
        "Direct path to csgo_weaponstickers.sq3 (fallback if databases.cfg missing)",
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
    g_cvDeferLive = CreateConVar(
        "clutch_skins_defer_live",
        "1",
        "1 = web loadout changes apply after match (admins each round). 0 = apply immediately",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );
    g_cvOncePerMatch = CreateConVar(
        "clutch_skins_once_per_match",
        "1",
        "1 = full loadout sync once per match (no re-apply on death/respawn). sm_clutch_applyskins always forces.",
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
    RegServerCmd("sm_clutch_loadout_pending", Command_LoadoutPending, "Stage web loadout from DB (api-csgo player-sync)");

    AddCommandListener(ClutchBlockWsChatForPlayers, "say");
    AddCommandListener(ClutchBlockWsChatForPlayers, "say_team");
    AddCommandListener(ClutchBlockWsChatForPlayers, "say2");

    ClutchRegisterWsCommandBlocks();

    ConnectWeaponsDatabase();
    ConnectStickersDatabase();

    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
    HookEvent("cs_win_panel_match", Event_MatchOver, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

    PTaH(PTaH_GiveNamedItemPre, Hook, Clutch_GiveNamedItemPre);
    PTaH(PTaH_GiveNamedItemPost, Hook, Clutch_GiveNamedItemPost);

    UpdateRefreshTimer();
#if defined _clutch_gloves_included_
    RefreshGlovesNativeFlag();
#endif
#if defined _weapons_included_
    RefreshWeaponsReloadNativeFlag();
#endif
    CreateTimer(1.0, Timer_RecheckPluginNatives, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(3.0, Timer_RecheckPluginNatives, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RecheckPluginNatives(Handle timer) {
#if defined _clutch_gloves_included_
    RefreshGlovesNativeFlag();
#endif
#if defined _weapons_included_
    RefreshWeaponsReloadNativeFlag();
#endif
    return Plugin_Stop;
}

public void OnLibraryAdded(const char[] name) {
#if defined _clutch_gloves_included_
    if (StrEqual(name, "clutch_gloves")) {
        RefreshGlovesNativeFlag();
    }
#endif
#if defined _weapons_included_
    if (StrEqual(name, "weapons")) {
        RefreshWeaponsReloadNativeFlag();
    }
#endif
}

public void OnLibraryRemoved(const char[] name) {
#if defined _clutch_gloves_included_
    if (StrEqual(name, "clutch_gloves")) {
        g_bGlovesNativeReady = false;
    }
#endif
#if defined _weapons_included_
    if (StrEqual(name, "weapons")) {
        g_bWeaponsReloadNative = false;
        g_bWeaponsRefreshNative = false;
    }
#endif
}

public void OnConfigsExecuted() {
    g_cvWeaponsTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));
    char stickersPrefix[16];
    g_cvStickersTablePrefix.GetString(stickersPrefix, sizeof(stickersPrefix));
    Format(g_sStickersTable, sizeof(g_sStickersTable), "%sclutch_weaponstickers", stickersPrefix);
    Format(g_sLegacyStickersTable, sizeof(g_sLegacyStickersTable), "%sweaponstickers1", stickersPrefix);
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
#if defined _clutch_gloves_included_
    RefreshGlovesNativeFlag();
    if (!ClutchUseExternalGlovesPlugin()) {
        LogError(
            "[Clutch] z_clutch_gloves.smx not loaded — load z_clutch_gloves BEFORE z_clutch_skins_bridge"
        );
    }
#else
    LogError("[Clutch] clutch_gloves.inc missing — z_clutch_gloves.smx was not compiled");
#endif
#if defined _weapons_included_
    RefreshWeaponsReloadNativeFlag();
#endif
}

#if defined _clutch_gloves_included_
bool ClutchUseExternalGlovesPlugin() {
    return LibraryExists("clutch_gloves");
}

void RefreshGlovesNativeFlag() {
    if (!LibraryExists("clutch_gloves")) {
        g_bGlovesNativeReady = false;
        return;
    }

    g_bGlovesNativeReady = GetFeatureStatus(FeatureType_Native, "ClutchGloves_RefreshClient") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "ClutchGloves_ApplyClient") == FeatureStatus_Available;
    if (g_bGlovesNativeReady) {
        g_bLoggedGlovesNativeMissing = false;
        LogMessage("[Clutch] z_clutch_gloves natives ready");
    }
}

void ClutchGlovesRefreshClientSafe(int client) {
    RefreshGlovesNativeFlag();
    if (g_bGlovesNativeReady) {
        ClutchGloves_RefreshClient(client);
    } else if (LibraryExists("clutch_gloves")) {
        ServerCommand("sm_clutch_gloves_refresh");
    } else if (!g_bLoggedGlovesNativeMissing) {
        g_bLoggedGlovesNativeMissing = true;
        LogError(
            "[Clutch] z_clutch_gloves not ready — run: sm plugins unload z_clutch_skins_bridge; sm plugins unload z_clutch_gloves; sm plugins load z_clutch_gloves; sm plugins load z_clutch_skins_bridge"
        );
    }
}

void ClutchGlovesApplyClientSafe(int client) {
    RefreshGlovesNativeFlag();
    if (g_bGlovesNativeReady) {
        ClutchGloves_ApplyClient(client);
    } else if (LibraryExists("clutch_gloves")) {
        ServerCommand("sm_clutch_gloves_apply");
    }
}

bool ClutchGlovesIsClientUsingSafe(int client) {
    if (!g_bGlovesNativeReady) {
        return false;
    }
    return ClutchGloves_IsClientUsingGloves(client);
}
#endif

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
    if (g_hStickersDb != null) {
        delete g_hStickersDb;
        g_hStickersDb = null;
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
    EnsureTeamLoadoutTable();

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Connected to weapons database (v%s)", PLUGIN_VERSION);
    }
}

void ConnectStickersDatabase() {
    if (g_hStickersDb != null) {
        delete g_hStickersDb;
        g_hStickersDb = null;
    }

    g_bStickersTableReady = false;

    char dbName[64];
    g_cvStickersDb.GetString(dbName, sizeof(dbName));
    char stickersPrefix[16];
    g_cvStickersTablePrefix.GetString(stickersPrefix, sizeof(stickersPrefix));
    Format(g_sStickersTable, sizeof(g_sStickersTable), "%sclutch_weaponstickers", stickersPrefix);
    Format(g_sLegacyStickersTable, sizeof(g_sLegacyStickersTable), "%sweaponstickers1", stickersPrefix);

    Database.Connect(StickersDatabaseConnected, dbName);
}

public void StickersDatabaseConnected(Database database, const char[] error, any data) {
    if (database == null) {
        LogMessage(
            "[Clutch] stickers DB via databases.cfg failed: %s — trying direct SQLite path",
            error
        );
        ConnectStickersDatabaseDirect();
        return;
    }

    g_hStickersDb = database;

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Connected to stickers database table %s", g_sStickersTable);
    }

    EnsureClutchStickersTable();
}

void ClutchResolveStickersDbPath(char[] dbPath, int maxlen) {
    g_cvStickersDbPath.GetString(dbPath, maxlen);

    if (dbPath[0] == '\0') {
        BuildPath(Path_SM, dbPath, maxlen, "data/sqlite/csgo_weaponstickers.sq3");
        return;
    }

    if (dbPath[0] == '/' || (strlen(dbPath) > 2 && dbPath[1] == ':')) {
        return;
    }

    char relative[PLATFORM_MAX_PATH];
    strcopy(relative, sizeof(relative), dbPath);
    ReplaceString(relative, sizeof(relative), "addons/sourcemod/", "");
    ReplaceString(relative, sizeof(relative), "addons\\sourcemod\\", "");
    BuildPath(Path_SM, dbPath, maxlen, relative);
}

void ConnectStickersDatabaseDirect() {
    if (g_hStickersDb != null) {
        delete g_hStickersDb;
        g_hStickersDb = null;
    }

    char dbPath[PLATFORM_MAX_PATH];
    ClutchResolveStickersDbPath(dbPath, sizeof(dbPath));
    strcopy(g_sResolvedStickersDbPath, sizeof(g_sResolvedStickersDbPath), dbPath);

    KeyValues kv = new KeyValues("driver");
    kv.SetString("driver", "sqlite");
    kv.SetString("database", dbPath);

    char openError[256];
    Database database = SQL_ConnectCustom(kv, openError, sizeof(openError), true);
    delete kv;

    if (database == null) {
        LogError(
            "[Clutch] stickers SQL_ConnectCustom failed: %s (path=%s)",
            openError,
            dbPath
        );
        return;
    }

    g_hStickersDb = database;

    LogMessage("[Clutch] stickers DB path: %s (table %s)", dbPath, g_sStickersTable);

    EnsureClutchStickersTable();
    EnsureLegacyStickersTable();
}

void EnsureClutchStickersTable() {
    if (g_hStickersDb == null) {
        return;
    }

    char query[768];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid varchar(64) NOT NULL, weaponindex int NOT NULL DEFAULT 0, team varchar(2) NOT NULL DEFAULT 'CT', slot0 int NOT NULL DEFAULT 0, slot1 int NOT NULL DEFAULT 0, slot2 int NOT NULL DEFAULT 0, slot3 int NOT NULL DEFAULT 0, slot4 int NOT NULL DEFAULT 0, slot5 int NOT NULL DEFAULT 0, wear0 real NOT NULL DEFAULT 0, wear1 real NOT NULL DEFAULT 0, wear2 real NOT NULL DEFAULT 0, wear3 real NOT NULL DEFAULT 0, wear4 real NOT NULL DEFAULT 0, wear5 real NOT NULL DEFAULT 0, last_seen int NOT NULL DEFAULT 0, UNIQUE(steamid, weaponindex, team))",
        g_sStickersTable
    );
    g_hStickersDb.Query(T_EnsureClutchStickersTableCallback, query, _, DBPrio_High);
}

public void T_EnsureClutchStickersTableCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[Clutch] %s table create failed: %s", g_sStickersTable, error);
        return;
    }
    g_bStickersTableReady = true;
    LogMessage("[Clutch] %s table ready", g_sStickersTable);
}

void EnsureLegacyStickersTable() {
    if (g_hStickersDb == null) {
        return;
    }

    char query[768];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid varchar(64) NOT NULL, weaponindex int NOT NULL DEFAULT 0, slot0 int NOT NULL DEFAULT 0, slot1 int NOT NULL DEFAULT 0, slot2 int NOT NULL DEFAULT 0, slot3 int NOT NULL DEFAULT 0, slot4 int NOT NULL DEFAULT 0, slot5 int NOT NULL DEFAULT 0, wear0 real NOT NULL DEFAULT 0, wear1 real NOT NULL DEFAULT 0, wear2 real NOT NULL DEFAULT 0, wear3 real NOT NULL DEFAULT 0, wear4 real NOT NULL DEFAULT 0, wear5 real NOT NULL DEFAULT 0, rotation0 real NOT NULL DEFAULT 0, rotation1 real NOT NULL DEFAULT 0, rotation2 real NOT NULL DEFAULT 0, rotation3 real NOT NULL DEFAULT 0, rotation4 real NOT NULL DEFAULT 0, rotation5 real NOT NULL DEFAULT 0, last_seen int NOT NULL DEFAULT 0, UNIQUE(steamid, weaponindex))",
        g_sLegacyStickersTable
    );
    g_hStickersDb.Query(T_EnsureLegacyStickersTableCallback, query, _, DBPrio_High);
}

public void T_EnsureLegacyStickersTableCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[Clutch] %s table create failed: %s", g_sLegacyStickersTable, error);
        return;
    }
    LogMessage("[Clutch] %s table ready", g_sLegacyStickersTable);
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

void EnsureTeamLoadoutTable() {
    if (g_hWeaponsDb == null) {
        return;
    }

    char query[768];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %sclutch_team_loadout (steamid varchar(32) NOT NULL, team char(2) NOT NULL, weapon_id varchar(64) NOT NULL, paintkit int NOT NULL DEFAULT 0, wear real NOT NULL DEFAULT 0.15, seed int NOT NULL DEFAULT 0, stattrak int NOT NULL DEFAULT 0, stattrak_count int NOT NULL DEFAULT 0, nametag varchar(64) NOT NULL DEFAULT '', knife_index int NOT NULL DEFAULT -1, PRIMARY KEY (steamid, team, weapon_id))",
        g_sTablePrefix
    );
    g_hWeaponsDb.Query(T_EnsureTeamLoadoutTableCallback, query, _, DBPrio_High);
}

public void T_EnsureTeamLoadoutTableCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[Clutch] team loadout table create failed: %s", error);
    }
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
    ReplyToCommand(client, "[Clutch] Loadouts reaplicados. Luvas atualizam no proximo spawn.");
    return Plugin_Handled;
}

public Action Command_ApplySkins(int client, int args) {
#if defined _clutch_gloves_included_
    RefreshGlovesNativeFlag();
#endif
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            g_bPendingWebLoadout[i] = false;
            ClutchBeginForcedSync(i);
        }
    }
    ReplyToCommand(client, "[Clutch] Skins reaplicados. Luvas atualizam no proximo spawn.");
    return Plugin_Handled;
}

bool ClutchClientIsSkinAdmin(int client) {
    return (GetUserFlagBits(client) & ADMFLAG_GENERIC) != 0;
}

void ClutchRegisterWsCommandBlocks() {
    static const char WS_CONSOLE_CMDS[][] = {
        "buyammo1",
        "buyammo2",
        "sm_ws",
        "sm_skin",
        "sm_skins",
        "sm_knife",
        "sm_kf",
        "sm_wslang",
        "sm_seed",
        "sm_nametag",
    };

    for (int i = 0; i < sizeof(WS_CONSOLE_CMDS); i++) {
        AddCommandListener(ClutchBlockWsConsoleForPlayers, WS_CONSOLE_CMDS[i]);
    }
}

public Action ClutchBlockWsConsoleForPlayers(int client, const char[] command, int argc) {
    if (client <= 0 || IsFakeClient(client)) {
        return Plugin_Continue;
    }

    if (ClutchClientIsSkinAdmin(client)) {
        return Plugin_Continue;
    }

    PrintToChat(client, " [Clutch] Equipe skins pelo inventario no site.");
    return Plugin_Handled;
}

bool ClutchIsLiveMatch() {
    if (!g_cvDeferLive.BoolValue) {
        return false;
    }

    if (GameRules_GetProp("m_bWarmupPeriod", view_as<int>(Prop_Send))) {
        return false;
    }

    int rounds = GameRules_GetProp("m_totalRoundsPlayed", view_as<int>(Prop_Send));
    if (rounds > 0) {
        return true;
    }

    if (CS_GetTeamScore(CS_TEAM_CT) > 0 || CS_GetTeamScore(CS_TEAM_T) > 0) {
        return true;
    }

    return false;
}

int FindClientBySteam2(const char[] steam) {
    char clientSteam[32];
    char alt[32];

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }
        if (!ClutchGetClientSteam2(i, clientSteam, sizeof(clientSteam))) {
            continue;
        }
        if (StrEqual(clientSteam, steam, false)) {
            return i;
        }

        strcopy(alt, sizeof(alt), steam);
        if (alt[6] == '0') {
            alt[6] = '1';
        } else if (alt[6] == '1') {
            alt[6] = '0';
        }
        if (StrEqual(clientSteam, alt, false)) {
            return i;
        }
    }

    return 0;
}

void ClutchStageWebLoadout(int client) {
    if (client <= 0 || IsFakeClient(client) || !IsClientInGame(client)) {
        return;
    }

    g_bPendingWebLoadout[client] = true;

    if (!ClutchIsLiveMatch() || ClutchClientIsSkinAdmin(client)) {
        g_bPendingWebLoadout[client] = false;
        ClutchBeginForcedSync(client);
        return;
    }

    PrintToChat(client, " [Clutch] Skins do site aplicam no fim da partida.");
    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Staged web loadout for %N (apply at match end)", client);
    }
}

public Action Command_LoadoutPending(int args) {
    if (args >= 1) {
        char steam[32];
        GetCmdArg(1, steam, sizeof(steam));
        TrimString(steam);

        int client = FindClientBySteam2(steam);
        if (client > 0) {
            ClutchStageWebLoadout(client);
        } else if (g_cvDebug.BoolValue) {
            LogMessage("[Clutch] loadout_pending: %s not in game", steam);
        }
    } else {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                ClutchStageWebLoadout(i);
            }
        }
    }
    return Plugin_Handled;
}

bool ClutchIsBlockedWsChatToken(const char[] token) {
    return StrEqual(token, "ws", false)
        || StrEqual(token, "skin", false)
        || StrEqual(token, "skins", false)
        || StrEqual(token, "knife", false)
        || StrEqual(token, "kf", false)
        || StrEqual(token, "gloves", false)
        || StrEqual(token, "wslang", false)
        || StrEqual(token, "seed", false)
        || StrEqual(token, "nametag", false);
}

bool ClutchIsManualSkinChatCommand(const char[] msg) {
    if (msg[0] != '!' && msg[0] != '/') {
        return false;
    }

    char copy[64];
    strcopy(copy, sizeof(copy), msg[1]);
    TrimString(copy);
    if (copy[0] == '\0') {
        return false;
    }

    char token[32];
    int pos = BreakString(copy, token, sizeof(token));
    if (pos == -1) {
        strcopy(token, sizeof(token), copy);
    }

    return ClutchIsBlockedWsChatToken(token);
}

void ClutchStripSurroundingQuotes(char[] msg, int maxlen) {
    int len = strlen(msg);
    if (len >= 2 && msg[0] == '"' && msg[len - 1] == '"') {
        msg[len - 1] = '\0';
        strcopy(msg, maxlen, msg[1]);
    }
}

public Action ClutchBlockWsChatForPlayers(int client, const char[] command, int argc) {
    if (client <= 0 || IsFakeClient(client)) {
        return Plugin_Continue;
    }

    char msg[256];
    GetCmdArgString(msg, sizeof(msg));
    TrimString(msg);
    ClutchStripSurroundingQuotes(msg, sizeof(msg));

    if (!ClutchIsManualSkinChatCommand(msg)) {
        return Plugin_Continue;
    }

    if (ClutchClientIsSkinAdmin(client)) {
        return Plugin_Continue;
    }

    PrintToChat(client, " [Clutch] Equipe skins pelo inventario no site.");
    return Plugin_Handled;
}

void ClutchResetMatchLoadoutFlags() {
    for (int i = 1; i <= MaxClients; i++) {
        g_bMatchLoadoutSynced[i] = false;
    }
}

bool ClutchRoutineFullApplyBlocked(int client, bool force) {
    if (!g_cvOncePerMatch.BoolValue) {
        return false;
    }
    if (g_bAllowWeaponRegive[client]) {
        return false;
    }
    return force && g_bMatchLoadoutSynced[client];
}

void ClutchBeginForcedSync(int client) {
    g_bMatchLoadoutSynced[client] = false;
    g_bAllowWeaponRegive[client] = true;
#if defined _clutch_gloves_included_
    ClutchGlovesRefreshClientSafe(client);
    CreateTimer(0.25, Timer_ApplyGlovesAfterRefresh, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
#endif

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(FORCE_WEAPONS_AFTER_GLOVES_DELAY, Timer_ApplyWeaponsAfterGloves, pack, TIMER_FLAG_NO_MAPCHANGE);
}

#if defined _clutch_gloves_included_
public Action Timer_ApplyGlovesAfterRefresh(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
        ClutchGlovesApplyClientSafe(client);
    }
    return Plugin_Stop;
}
#endif

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
    g_bPendingWebLoadout[client] = false;
    g_fLastApplyTime[client] = 0.0;
    g_iLastKnifePaint[client] = 0;
    g_iLastGloveGroup[client] = 0;
    g_iLastGlovePaint[client] = 0;
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client] = 0;
    g_iGloveApplyGen[client] = 0;
    g_bForceGloveApply[client] = false;
    g_bAllowWeaponRegive[client] = false;
    g_bMatchLoadoutSynced[client] = false;
    g_iReapplyGen[client] = 0;
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
    ClutchClearStickerCache(client);
}

public void OnClientPutInServer(int client) {
    if (IsFakeClient(client)) {
        return;
    }
    SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
#if defined _clutch_gloves_included_
    ClutchGlovesRefreshClientSafe(client);
#endif
}

public void OnClientAuthorized(int client, const char[] authString) {
    if (IsFakeClient(client)) {
        return;
    }
#if defined _clutch_gloves_included_
    ClutchGlovesRefreshClientSafe(client);
#endif
    g_fLastApplyTime[client] = 0.0;
    if (g_bMatchLoadoutSynced[client]) {
        return;
    }
    CreateTimer(0.4, Timer_ApplySkinsOnSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
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
    int userid = GetClientUserId(client);
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        ClutchGlovesRefreshClientSafe(client);
    }
#endif
    if (g_cvOncePerMatch.BoolValue && g_bMatchLoadoutSynced[client]) {
        // Skins once-per-match, but weapons respawn fresh — reload stickers from DB.
        CreateTimer(0.5, Timer_RefreshStickersOnSpawn, userid, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    CreateTimer(0.4, Timer_ApplySkinsOnSpawn, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RefreshStickersOnSpawn(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Stop;
    }

    char steamId[32];
    if (ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
        QueryPlayerStickers(client, steamId, 0);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    CreateTimer(0.6, Timer_DelayedStickerReapply, pack, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_DelayedStickerReapply(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client)) {
        ClutchReapplyStickersOnPlayerWeapons(client);
    }
    return Plugin_Stop;
}

public Action Timer_ApplySkinsOnSpawn(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Stop;
    }
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin() && IsPlayerAlive(client)) {
        ClutchGlovesApplyClientSafe(client);
    }
#endif
    ApplyClientSkins(client, true);
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    CreateTimer(3.0, Timer_RoundStartApply, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartApply(Handle timer) {
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client)) {
            continue;
        }
        if (g_cvOncePerMatch.BoolValue && g_bMatchLoadoutSynced[client]) {
            continue;
        }
        if (
            g_cvDeferLive.BoolValue
            && ClutchIsLiveMatch()
            && !ClutchClientIsSkinAdmin(client)
        ) {
            continue;
        }
        ApplyClientSkins(client, true);
    }
    return Plugin_Stop;
}

public void Event_MatchOver(Event event, const char[] name, bool dontBroadcast) {
    ClutchResetMatchLoadoutFlags();
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }
        if (!g_bPendingWebLoadout[client]) {
            continue;
        }
        g_bPendingWebLoadout[client] = false;
        ClutchBeginForcedSync(client);
        if (g_cvDebug.BoolValue) {
            LogMessage("[Clutch] Applied staged web loadout at match end for %N", client);
        }
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    CreateTimer(0.35, Timer_ApplyAfterTeamChange, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplyAfterTeamChange(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
        if (!g_cvOncePerMatch.BoolValue || !g_bMatchLoadoutSynced[client]) {
            ApplyClientSkins(client, true);
        }
    }
    return Plugin_Stop;
}

public Action Clutch_GiveNamedItemPre(
    int client,
    char classname[64],
    CEconItemView &item,
    bool &ignoredItemView,
    bool &originIsNull,
    float origin[3]
) {
    return Plugin_Continue;
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
    if (entityPaint == paintkit && g_iAppliedPaintkit[client][idx] == paintkit) {
        return;
    }

    ApplyCachedSkinToEntity(client, entity, idx, IsMeleeClassname(cn), true);
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
    int csTeam = GetClientTeam(client);
    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);

        if (!ClutchWeaponAllowedForTeam(weaponKey, csTeam)) {
            ClearSlotCache(client, i);
            continue;
        }

        if (IsMeleeWeaponKey(weaponKey)) {
            ClearSlotCache(client, i);
        }
    }
    g_CachedKnifeClass[client][0] = '\0';
    g_iLastKnifePaint[client] = 0;
}

void PrepareTeamLoadoutCaches(int client) {
    int csTeam = GetClientTeam(client);
    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);

        if (!ClutchWeaponAllowedForTeam(weaponKey, csTeam)) {
            ClearSlotCache(client, i);
            continue;
        }

        if (!IsMeleeWeaponKey(weaponKey)) {
            ClearSlotCache(client, i);
        }
    }

    g_CachedKnifeClass[client][0] = '\0';
    g_iLastKnifePaint[client] = 0;
}

bool ApplyCachedSkinToEntity(int client, int entity, int idx, bool isKnife, bool force = false, bool allowRegive = false) {
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

    if (!isKnife && allowRegive && ClutchClientHasGlovesLoaded(client)) {
        if (GetGameTime() - g_fLastWeaponRegive[client][idx] < WEAPON_REGIVE_COOLDOWN) {
            // fall through to SetClutchWeaponProps
        } else if (ClutchRefreshWeaponSlot(client, idx)) {
            g_fLastWeaponRegive[client][idx] = GetGameTime();
            g_iAppliedPaintkit[client][idx] = paintkit;
            if (g_cvDebug.BoolValue) {
                LogMessage(
                    "[Clutch] bridge re-give %s paintkit %d for %N",
                    g_ClutchWeaponKeys[idx],
                    paintkit,
                    client
                );
            }
            return true;
        }
    }

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
        return true;
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
}

void ForceReapplyPlayerGloves(int client) {
    g_bForceGloveApply[client] = true;
    g_bGlovesPending[client] = false;
    g_iGloveQueryGen[client]++;
    g_iGloveApplyGen[client]++;

    char steamId[32];
    if (!ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
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
    if (!ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
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

public Action Timer_ApplyKnifeSkinFromCache(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || g_CachedKnifeClass[client][0] == '\0') {
        return Plugin_Stop;
    }

    int idx = GetClutchIndexForClassname(client, g_CachedKnifeClass[client]);
    if (idx < 0 || g_CachedPaintkit[client][idx] <= 0) {
        return Plugin_Stop;
    }

    int weapon = FindPlayerWeapon(client, g_CachedKnifeClass[client]);
    if (weapon == -1) {
        return Plugin_Stop;
    }

    ApplyCachedSkinToEntity(client, weapon, idx, true, true, false);
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

    bool freshItem = GetEntProp(weapon, Prop_Send, "m_iItemIDHigh") < 16384;
    if (freshItem) {
        SetEntProp(weapon, Prop_Send, "m_iItemIDLow", -1);
        SetEntProp(weapon, Prop_Send, "m_iItemIDHigh", g_iItemIdHigh++);
    }
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

    ClutchSetOriginalOwnerXuid(client, weapon);
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

    ClutchNetworkUpdateWeaponSkin(weapon);
    if (!isKnife) {
        ClutchMirrorSkinToViewModels(client, weapon);
        int stickerIdx = ClutchIndexFromWeaponEntity(client, weapon);
        if (stickerIdx >= 0) {
            ClutchApplyStickersForWeapon(client, weapon, stickerIdx);
            ClutchScheduleStickerReapplyPasses(client, weapon, stickerIdx);
        }
    }
    if (isKnife && ClutchClientHasGlovesLoaded(client)) {
        return;
    } else if (isKnife) {
        ClutchRequestClientModelUpdate(client);
    }
}

void ClutchSetOriginalOwnerXuid(int client, int entity) {
    int accountId = GetSteamAccountID(client);
    if (HasEntProp(entity, Prop_Send, "m_OriginalOwnerXuidLow")) {
        SetEntProp(entity, Prop_Send, "m_OriginalOwnerXuidLow", accountId);
    }
    if (HasEntProp(entity, Prop_Send, "m_OriginalOwnerXuidHigh")) {
        SetEntProp(entity, Prop_Send, "m_OriginalOwnerXuidHigh", 0);
    }
}

void ClutchCopyWeaponSkinProps(int source, int target) {
    if (!IsPaintableWeaponEntity(source) || !IsPaintableWeaponEntity(target)) {
        return;
    }

    SetEntProp(target, Prop_Send, "m_iItemIDLow", GetEntProp(source, Prop_Send, "m_iItemIDLow"));
    SetEntProp(target, Prop_Send, "m_iItemIDHigh", GetEntProp(source, Prop_Send, "m_iItemIDHigh"));
    SetEntProp(target, Prop_Send, "m_nFallbackPaintKit", GetEntProp(source, Prop_Send, "m_nFallbackPaintKit"));
    SetEntPropFloat(target, Prop_Send, "m_flFallbackWear", GetEntPropFloat(source, Prop_Send, "m_flFallbackWear"));
    SetEntProp(target, Prop_Send, "m_nFallbackSeed", GetEntProp(source, Prop_Send, "m_nFallbackSeed"));
    SetEntProp(target, Prop_Send, "m_nFallbackStatTrak", GetEntProp(source, Prop_Send, "m_nFallbackStatTrak"));
    SetEntProp(target, Prop_Send, "m_iEntityQuality", GetEntProp(source, Prop_Send, "m_iEntityQuality"));
    SetEntProp(target, Prop_Send, "m_iAccountID", GetEntProp(source, Prop_Send, "m_iAccountID"));
    ClutchNetworkUpdateWeaponSkin(target);
}

void ClutchMirrorSkinToViewModels(int client, int weapon) {
    if (client <= 0 || weapon <= 0 || !IsValidEntity(weapon)) {
        return;
    }

    if (HasEntProp(client, Prop_Data, "m_hViewModel")) {
        for (int slot = 0; slot <= 1; slot++) {
            int viewModel = GetEntPropEnt(client, Prop_Data, "m_hViewModel", slot);
            if (viewModel != -1 && IsValidEntity(viewModel) && IsPaintableWeaponEntity(viewModel)) {
                ClutchCopyWeaponSkinProps(weapon, viewModel);
            }
        }
    }

    int predicted = -1;
    while ((predicted = FindEntityByClassname(predicted, "predicted_viewmodel")) != -1) {
        if (!IsValidEntity(predicted)) {
            continue;
        }

        int owner = GetEntPropEnt(predicted, Prop_Send, "m_hOwner");
        if (owner != client) {
            continue;
        }

        if (HasEntProp(predicted, Prop_Send, "m_hWeapon")) {
            int linkedWeapon = GetEntPropEnt(predicted, Prop_Send, "m_hWeapon");
            if (linkedWeapon != weapon) {
                continue;
            }
        }

        if (!IsPaintableWeaponEntity(predicted)) {
            continue;
        }

        ClutchCopyWeaponSkinProps(weapon, predicted);
    }
}

int ClutchIndexFromDefIndex(int defIndex) {
    if (defIndex <= 0) {
        return -1;
    }

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        if (g_ClutchWeaponDefIndex[i] == defIndex) {
            return i;
        }
    }

    return -1;
}

int ClutchIndexFromWeaponEntity(int client, int weapon) {
    if (weapon <= 0 || !IsValidEntity(weapon)) {
        return -1;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return GetClutchIndexForClassname(client, classname);
}

int ClutchStickerTeamSlot(int team) {
    return team == CS_TEAM_CT ? 1 : 0;
}

void ClutchClearStickerCache(int client) {
    for (int t = 0; t < 2; t++) {
        for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
            for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
                g_iStickerSlots[client][t][i][s] = 0;
                g_fStickerWears[client][t][i][s] = 0.0;
            }
        }
    }
}

bool ClutchWeaponHasStickerCache(int client, int idx) {
    if (idx < 0 || idx >= CLUTCH_WEAPON_SLOTS) {
        return false;
    }

    int teamSlot = ClutchStickerTeamSlot(GetClientTeam(client));

    for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
        if (g_iStickerSlots[client][teamSlot][idx][s] != 0) {
            return true;
        }
    }

    return false;
}

bool ClutchEnsureEconItemInitialized(int client, int entity) {
    if (client <= 0 || entity <= 0 || !IsValidEntity(entity)) {
        return false;
    }

    if (!HasEntProp(entity, Prop_Send, "m_iItemIDHigh")) {
        return false;
    }

    if (GetEntProp(entity, Prop_Send, "m_iItemIDHigh") >= 16384) {
        return true;
    }

    SetEntProp(entity, Prop_Send, "m_iItemIDLow", -1);
    SetEntProp(entity, Prop_Send, "m_iItemIDHigh", g_iItemIdHigh++);
    SetEntProp(entity, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
    if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity")) {
        SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
    }
    if (HasEntProp(entity, Prop_Send, "m_hPrevOwner")) {
        SetEntPropEnt(entity, Prop_Send, "m_hPrevOwner", -1);
    }
    if (HasEntProp(entity, Prop_Send, "m_bInitialized")) {
        SetEntProp(entity, Prop_Send, "m_bInitialized", 1);
    }

    return true;
}

int ClutchSupportedStickerSlotsForIndex(int idx) {
    if (idx < 0 || idx >= CLUTCH_WEAPON_SLOTS) {
        return CLUTCH_SITE_STICKER_SLOTS;
    }

    int defIndex = g_ClutchWeaponDefIndex[idx];
    if (defIndex <= 0) {
        return CLUTCH_SITE_STICKER_SLOTS;
    }

    CEconItemDefinition itemDef = PTaH_GetItemDefinitionByDefIndex(defIndex);
    if (itemDef == view_as<CEconItemDefinition>(0)) {
        return CLUTCH_SITE_STICKER_SLOTS;
    }

    int supported = itemDef.GetNumSupportedStickerSlots();
    if (supported <= 0) {
        return CLUTCH_SITE_STICKER_SLOTS;
    }

    if (supported > CLUTCH_STICKER_SLOTS) {
        supported = CLUTCH_STICKER_SLOTS;
    }

    return supported;
}

void ClutchWriteStickerSlotAttributes(CAttributeList attrList, int slot, int stickerId, float wear) {
    if (stickerId <= 0) {
        return;
    }

    int idAttr = 113 + slot * 4;
    if (wear < 0.0) {
        wear = 0.0;
    } else if (wear > 1.0) {
        wear = 1.0;
    }

    attrList.SetOrAddAttributeValue(idAttr, stickerId);
    attrList.SetOrAddAttributeValue(idAttr + 1, wear);
    attrList.SetOrAddAttributeValue(idAttr + 2, 1.0);
}

void ClutchApplyStickerAttrsToEntity(int client, int entity, int idx, int teamSlot) {
    CEconItemView itemView = PTaH_GetEconItemViewFromEconEntity(entity);
    CAttributeList demoAttrs = itemView.NetworkedDynamicAttributesForDemos;
    CAttributeList staticAttrs = itemView.AttributeList;
    int engineMax = ClutchSupportedStickerSlotsForIndex(idx);

    if (g_cvDebug.BoolValue && engineMax < CLUTCH_SITE_STICKER_SLOTS) {
        LogMessage(
            "[Clutch] engine reports %d sticker slots for %s — applying all %d site slots",
            engineMax,
            g_ClutchWeaponKeys[idx],
            CLUTCH_SITE_STICKER_SLOTS
        );
    }

    for (int s = 0; s < CLUTCH_SITE_STICKER_SLOTS; s++) {
        int stickerId = g_iStickerSlots[client][teamSlot][idx][s];
        if (stickerId == 0) {
            continue;
        }
        float wear = g_fStickerWears[client][teamSlot][idx][s];
        ClutchWriteStickerSlotAttributes(demoAttrs, s, stickerId, wear);
        ClutchWriteStickerSlotAttributes(staticAttrs, s, stickerId, wear);
    }
}

bool ClutchApplyStickersToEntity(int client, int entity, int idx) {
    if (
        client <= 0
        || entity <= 0
        || idx < 0
        || idx >= CLUTCH_WEAPON_SLOTS
        || IsMeleeWeaponKey(g_ClutchWeaponKeys[idx])
        || !IsPaintableWeaponEntity(entity)
        || !ClutchWeaponHasStickerCache(client, idx)
    ) {
        return false;
    }

    ClutchEnsureEconItemInitialized(client, entity);

    int teamSlot = ClutchStickerTeamSlot(GetClientTeam(client));
    bool updated = false;

    for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
        if (g_iStickerSlots[client][teamSlot][idx][s] != 0) {
            updated = true;
            break;
        }
    }

    if (updated) {
        ClutchApplyStickerAttrsToEntity(client, entity, idx, teamSlot);
    }

    return updated;
}

void ClutchMirrorStickersToViewModels(int client, int weapon, int idx) {
    if (client <= 0 || weapon <= 0 || idx < 0 || !IsValidEntity(weapon)) {
        return;
    }

    if (HasEntProp(client, Prop_Data, "m_hViewModel")) {
        for (int slot = 0; slot <= 1; slot++) {
            int viewModel = GetEntPropEnt(client, Prop_Data, "m_hViewModel", slot);
            if (viewModel != -1 && IsValidEntity(viewModel) && IsPaintableWeaponEntity(viewModel)) {
                ClutchApplyStickersToEntity(client, viewModel, idx);
            }
        }
    }

    int predicted = -1;
    while ((predicted = FindEntityByClassname(predicted, "predicted_viewmodel")) != -1) {
        if (!IsValidEntity(predicted)) {
            continue;
        }

        int owner = GetEntPropEnt(predicted, Prop_Send, "m_hOwner");
        if (owner != client) {
            continue;
        }

        if (HasEntProp(predicted, Prop_Send, "m_hWeapon")) {
            int linkedWeapon = GetEntPropEnt(predicted, Prop_Send, "m_hWeapon");
            if (linkedWeapon != weapon) {
                continue;
            }
        }

        if (!IsPaintableWeaponEntity(predicted)) {
            continue;
        }

        ClutchApplyStickersToEntity(client, predicted, idx);
    }
}

void ClutchApplyStickersForWeapon(int client, int weapon, int idx) {
    bool updated = ClutchApplyStickersToEntity(client, weapon, idx);
    if (updated) {
        ClutchMirrorStickersToViewModels(client, weapon, idx);
        PTaH_ForceFullUpdate(client);

        if (g_cvDebug.BoolValue) {
            char classname[64];
            GetEntityClassname(weapon, classname, sizeof(classname));
            int maxSlots = ClutchSupportedStickerSlotsForIndex(idx);
            LogMessage(
                "[Clutch] Applied stickers on %s (idx %d, engineMaxSlots %d) for %N",
                classname,
                idx,
                maxSlots,
                client
            );
            CEconItemView verifyView = PTaH_GetEconItemViewFromEconEntity(weapon);
            for (int s = 0; s < CLUTCH_SITE_STICKER_SLOTS; s++) {
                int cached = g_iStickerSlots[client][ClutchStickerTeamSlot(GetClientTeam(client))][idx][s];
                int applied = verifyView.GetStickerAttributeBySlotIndex(s, EStickerAttribute_ID, 0);
                if (cached != 0 || applied != 0) {
                    LogMessage(
                        "[Clutch] sticker slot %d cached=%d applied=%d for %N",
                        s,
                        cached,
                        applied,
                        client
                    );
                }
            }
        }
    }
}

void ClutchScheduleStickerReapplyPasses(int client, int weapon, int idx) {
    if (client <= 0 || weapon <= 0 || idx < 0 || !IsValidEntity(weapon)) {
        return;
    }

    int userid = GetClientUserId(client);
    for (int i = 0; i < STICKER_REAPPLY_PASS_COUNT; i++) {
        DataPack pack = new DataPack();
        pack.WriteCell(userid);
        pack.WriteCell(EntIndexToEntRef(weapon));
        pack.WriteCell(idx);
        CreateTimer(g_fStickerReapplyDelays[i], Timer_StickerReapplyPass, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_StickerReapplyPass(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    int weaponRef = pack.ReadCell();
    int idx = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    int weapon = EntRefToEntIndex(weaponRef);
    if (client <= 0 || !IsClientInGame(client) || weapon == -1 || !IsValidEntity(weapon)) {
        return Plugin_Stop;
    }

    if (!ClutchWeaponHasStickerCache(client, idx)) {
        return Plugin_Stop;
    }

    ClutchApplyStickersForWeapon(client, weapon, idx);
    return Plugin_Stop;
}

void ClutchReapplyStickersOnPlayerWeapons(int client) {
    if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client)) {
        return;
    }

    int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int i = 0; i < size; i++) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon == -1 || !IsValidEntity(weapon)) {
            continue;
        }

        int idx = ClutchIndexFromWeaponEntity(client, weapon);
        if (idx >= 0 && ClutchWeaponHasStickerCache(client, idx)) {
            ClutchApplyStickersForWeapon(client, weapon, idx);
        }
    }
}

bool ClutchGiveCachedWeapon(int client, int idx) {
    if (idx < 0 || idx >= CLUTCH_WEAPON_SLOTS || IsMeleeWeaponKey(g_ClutchWeaponKeys[idx])) {
        return false;
    }

    int paintkit = g_CachedPaintkit[client][idx];
    if (paintkit <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return false;
    }

    char weaponClass[32];
    strcopy(weaponClass, sizeof(weaponClass), g_ClutchWeaponKeys[idx]);

    if (FindPlayerWeapon(client, weaponClass) != -1) {
        return false;
    }

    int weapon = GivePlayerItem(client, weaponClass);
    if (weapon == -1) {
        return false;
    }

    SetClutchWeaponProps(
        client,
        weapon,
        paintkit,
        g_CachedWear[client][idx],
        g_CachedSeed[client][idx],
        g_CachedTrak[client][idx],
        g_CachedTrakCount[client][idx],
        g_CachedTag[client][idx],
        false
    );
    g_iAppliedPaintkit[client][idx] = paintkit;

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Gave %s paintkit %d for %N", weaponClass, paintkit, client);
    }
    return true;
}

bool ClutchRefreshWeaponSlot(int client, int idx) {
    if (idx < 0 || idx >= CLUTCH_WEAPON_SLOTS || IsMeleeWeaponKey(g_ClutchWeaponKeys[idx])) {
        return false;
    }

    int paintkit = g_CachedPaintkit[client][idx];
    if (paintkit <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return false;
    }

    char weaponClass[32];
    strcopy(weaponClass, sizeof(weaponClass), g_ClutchWeaponKeys[idx]);

    int clip = -1;
    int reserve = -1;
    int ammoOffset = -1;
    int ammo = -1;
    bool found = false;

    int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int i = 0; i < size; i++) {
        int existing = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (!IsValidEntity(existing)) {
            continue;
        }

        char classname[64];
        GetEntityClassname(existing, classname, sizeof(classname));
        if (!StrEqual(classname, weaponClass, false)) {
            continue;
        }

        int ammoType = GetEntProp(existing, Prop_Data, "m_iPrimaryAmmoType");
        if (ammoType >= 0) {
            ammoOffset = FindDataMapInfo(client, "m_iAmmo") + (ammoType * 4);
            if (ammoOffset > 0) {
                ammo = GetEntData(client, ammoOffset);
            }
        }
        clip = GetEntProp(existing, Prop_Send, "m_iClip1");
        reserve = GetEntProp(existing, Prop_Send, "m_iPrimaryReserveAmmoCount");

        RemovePlayerItem(client, existing);
        if (IsValidEntity(existing)) {
            AcceptEntityInput(existing, "KillHierarchy");
        }
        found = true;
        break;
    }

    if (!found) {
        return ClutchGiveCachedWeapon(client, idx);
    }

    int newWeapon = GivePlayerItem(client, weaponClass);
    if (newWeapon == -1) {
        return false;
    }

    SetClutchWeaponProps(
        client,
        newWeapon,
        paintkit,
        g_CachedWear[client][idx],
        g_CachedSeed[client][idx],
        g_CachedTrak[client][idx],
        g_CachedTrakCount[client][idx],
        g_CachedTag[client][idx],
        false
    );
    g_iAppliedPaintkit[client][idx] = paintkit;

    if (clip != -1) {
        SetEntProp(newWeapon, Prop_Send, "m_iClip1", clip);
    }
    if (reserve != -1) {
        SetEntProp(newWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", reserve);
    }
    if (ammoOffset > 0 && ammo != -1) {
        DataPack ammoPack = new DataPack();
        ammoPack.WriteCell(GetClientUserId(client));
        ammoPack.WriteCell(ammoOffset);
        ammoPack.WriteCell(ammo);
        CreateTimer(0.1, Timer_RestoreWeaponAmmo, ammoPack, TIMER_FLAG_NO_MAPCHANGE);
    }

    return true;
}

bool ClutchRegiveKnife(int client) {
    if (g_CachedKnifeClass[client][0] == '\0') {
        return false;
    }

    int idx = GetClutchIndexForClassname(client, g_CachedKnifeClass[client]);
    if (idx < 0) {
        return false;
    }

    int paintkit = g_CachedPaintkit[client][idx];
    if (paintkit <= 0) {
        return false;
    }

    char knifeClass[64];
    strcopy(knifeClass, sizeof(knifeClass), g_CachedKnifeClass[client]);

    int existing = FindPlayerWeapon(client, knifeClass);
    if (existing != -1) {
        RemovePlayerItem(client, existing);
        if (IsValidEntity(existing)) {
            AcceptEntityInput(existing, "KillHierarchy");
        }
    }

    int newKnife = GivePlayerItem(client, knifeClass);
    if (newKnife == -1) {
        return false;
    }

    SetClutchWeaponProps(
        client,
        newKnife,
        paintkit,
        g_CachedWear[client][idx],
        g_CachedSeed[client][idx],
        g_CachedTrak[client][idx],
        g_CachedTrakCount[client][idx],
        g_CachedTag[client][idx],
        true
    );
    g_iAppliedPaintkit[client][idx] = paintkit;

    if (g_cvDebug.BoolValue) {
        LogMessage("[Clutch] Re-gave %s paintkit %d for %N", knifeClass, paintkit, client);
    }
    return true;
}

public Action Timer_RestoreWeaponAmmo(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    int ammoOffset = pack.ReadCell();
    int ammo = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && ammoOffset > 0) {
        SetEntData(client, ammoOffset, ammo, 4, true);
    }
    return Plugin_Stop;
}

void ClutchNetworkUpdate(int entity) {
    int offset = FindSendPropInfo("CBaseEntity", "m_nModelIndex");
    if (offset != -1) {
        ChangeEdictState(entity, offset);
    }
}

void ClutchNetworkUpdateWeaponSkin(int entity) {
    int paintOffset = FindSendPropInfo("CBaseAttributableItem", "m_nFallbackPaintKit");
    if (paintOffset != -1) {
        ChangeEdictState(entity, paintOffset);
    }
    int wearOffset = FindSendPropInfo("CBaseAttributableItem", "m_flFallbackWear");
    if (wearOffset != -1) {
        ChangeEdictState(entity, wearOffset);
    }
    int seedOffset = FindSendPropInfo("CBaseAttributableItem", "m_nFallbackSeed");
    if (seedOffset != -1) {
        ChangeEdictState(entity, seedOffset);
    }
    int idLowOffset = FindSendPropInfo("CBaseAttributableItem", "m_iItemIDLow");
    if (idLowOffset != -1) {
        ChangeEdictState(entity, idLowOffset);
    }
    int idHighOffset = FindSendPropInfo("CBaseAttributableItem", "m_iItemIDHigh");
    if (idHighOffset != -1) {
        ChangeEdictState(entity, idHighOffset);
    }
    ClutchNetworkUpdate(entity);
}

#if defined _weapons_included_
void RefreshWeaponsReloadNativeFlag() {
    g_bWeaponsReloadNative = false;
    g_bWeaponsRefreshNative = false;

    if (!LibraryExists("weapons")) {
        return;
    }

    g_bWeaponsReloadNative =
        GetFeatureStatus(FeatureType_Native, "Weapons_ReloadClientData") == FeatureStatus_Available;
    g_bWeaponsRefreshNative =
        GetFeatureStatus(FeatureType_Native, "Weapons_RefreshWeapon") == FeatureStatus_Available;

    if (g_bWeaponsReloadNative) {
        g_bLoggedMissingReloadNative = false;
    }
    if (g_bWeaponsRefreshNative) {
        g_bLoggedMissingRefreshNative = false;
    }

    if (!g_bWeaponsReloadNative && !g_bLoggedMissingReloadNative) {
        g_bLoggedMissingReloadNative = true;
        LogMessage(
            "[Clutch] weapons.smx has no Weapons_ReloadClientData native — paint may stay stale. Run: bash scripts/patch-weapons-reload-native.sh"
        );
    }
    if (!g_bWeaponsRefreshNative && !g_bLoggedMissingRefreshNative && g_cvDebug.BoolValue) {
        // Non-critical: bridge re-gives weapons itself when this native is absent.
        g_bLoggedMissingRefreshNative = true;
        LogMessage(
            "[Clutch] weapons.smx has no Weapons_RefreshWeapon native (optional) — bridge will re-give weapons directly."
        );
    }
    if (g_bWeaponsReloadNative && g_bWeaponsRefreshNative && g_cvDebug.BoolValue) {
        LogMessage("[Clutch] weapons.smx reload/refresh natives ready");
    }
}

void TryReloadWeaponsPluginData(int client) {
    if (!LibraryExists("weapons") || !g_bWeaponsReloadNative) {
        return;
    }
    Weapons_ReloadClientData(client);
}
#endif

void ApplyAllCachedWeaponsToClient(int client, bool force, bool allowRegive = false) {
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
            if (force && allowRegive) {
                ClutchGiveCachedWeapon(client, i);
            }
            continue;
        }

        ApplyCachedSkinToEntity(client, weapon, i, IsMeleeWeaponKey(weaponKey), force, allowRegive);
    }

    ClutchReapplyStickersOnPlayerWeapons(client);
    ClutchBridgeUpdateClientModel(client);
}

/**
 * Refreshing the player model strips the glove wearable. Let z_clutch_gloves own
 * the model when it runs (even if its natives are not bound yet), so warmup reloads
 * do not wipe gloves.
 */
void ClutchBridgeUpdateClientModel(int client) {
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        return;
    }
#endif
    if (ClutchClientHasGlovesLoaded(client)) {
        return;
    }
    CS_UpdateClientModel(client);
}

void ScheduleWeaponsAfterGlovesApply(int client, bool force, bool skipWeaponsReload = false) {
    if (!IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(force ? 1 : 0);
    pack.WriteCell(skipWeaponsReload ? 1 : 0);
    CreateTimer(FORCE_WEAPONS_AFTER_GLOVES_DELAY, Timer_ApplyCachedWeaponsDelayed, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplyCachedWeaponsDelayed(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    bool force = pack.ReadCell() == 1;
    bool skipWeaponsReload = pack.ReadCell() == 1;
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    bool allowRegive = force;
#if defined _weapons_included_
    if (!skipWeaponsReload) {
        RefreshWeaponsReloadNativeFlag();
        TryReloadWeaponsPluginData(client);
    }
#endif
    ApplyAllCachedWeaponsToClient(client, force, allowRegive);
    ScheduleForceReapply(client, force, allowRegive);
    return Plugin_Stop;
}

void ScheduleForceReapply(int client, bool force, bool allowRegive = false) {
    if (!IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    g_iReapplyGen[client]++;
    int gen = g_iReapplyGen[client];
    int userid = GetClientUserId(client);
    for (int i = 0; i < REAPPLY_PASS_COUNT; i++) {
        if (g_cvOncePerMatch.BoolValue && !allowRegive && i > 0) {
            break;
        }
        DataPack pack = new DataPack();
        pack.WriteCell(userid);
        pack.WriteCell(force ? 1 : 0);
        pack.WriteCell(i);
        pack.WriteCell(gen);
        pack.WriteCell((allowRegive && i == 0) ? 1 : 0);
        CreateTimer(g_fReapplyDelays[i], Timer_ForceReapplyPass, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ForceReapplyPass(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    bool force = pack.ReadCell() == 1;
    int pass = pack.ReadCell();
    int gen = pack.ReadCell();
    bool allowRegive = pack.ReadCell() == 1;
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    if (gen != g_iReapplyGen[client]) {
        return Plugin_Stop;
    }

    ApplyAllCachedWeaponsToClient(client, force, allowRegive);

    if (allowRegive && pass == 0) {
        ClutchRegiveKnife(client);
    }

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
        // update=true so kgns swaps the knife model immediately (not only on next spawn/death).
        Weapons_SetClientKnife(client, knife, IsPlayerAlive(client));
    }
#endif
}

int GetClutchIndexForWeaponId(const char[] weaponId) {
    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        if (StrEqual(weaponId, g_ClutchWeaponKeys[i], false)) {
            return i;
        }
    }
    return -1;
}

bool ClutchWeaponAllowedForTeam(const char[] weaponKey, int csTeam) {
    if (csTeam != CS_TEAM_T && csTeam != CS_TEAM_CT) {
        return true;
    }

    if (
        StrEqual(weaponKey, "weapon_glock", false)
        || StrEqual(weaponKey, "weapon_tec9", false)
        || StrEqual(weaponKey, "weapon_galilar", false)
        || StrEqual(weaponKey, "weapon_ak47", false)
        || StrEqual(weaponKey, "weapon_g3sg1", false)
        || StrEqual(weaponKey, "weapon_mac10", false)
        || StrEqual(weaponKey, "weapon_sawedoff", false)
    ) {
        return csTeam == CS_TEAM_T;
    }

    if (
        StrEqual(weaponKey, "weapon_hkp2000", false)
        || StrEqual(weaponKey, "weapon_usp_silencer", false)
        || StrEqual(weaponKey, "weapon_fiveseven", false)
        || StrEqual(weaponKey, "weapon_cz75a", false)
        || StrEqual(weaponKey, "weapon_famas", false)
        || StrEqual(weaponKey, "weapon_m4a1", false)
        || StrEqual(weaponKey, "weapon_m4a1_silencer", false)
        || StrEqual(weaponKey, "weapon_aug", false)
        || StrEqual(weaponKey, "weapon_sg556", false)
        || StrEqual(weaponKey, "weapon_scar20", false)
        || StrEqual(weaponKey, "weapon_mp9", false)
        || StrEqual(weaponKey, "weapon_mag7", false)
    ) {
        return csTeam == CS_TEAM_CT;
    }

    return true;
}

/** Deagle, AWP, etc. — per-side paints live in clutch_team_loadout, not kgns columns. */
bool ClutchIsSharedWeaponKey(const char[] weaponKey) {
    if (IsMeleeWeaponKey(weaponKey)) {
        return false;
    }
    return ClutchWeaponAllowedForTeam(weaponKey, CS_TEAM_T)
        && ClutchWeaponAllowedForTeam(weaponKey, CS_TEAM_CT);
}

void QueryKgnsLoadout(int client, const char[] steamId, int altAttempt, bool force) {
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

void QueryTeamLoadout(int client, const char[] steamId, int altAttempt, bool force) {
    if (g_hWeaponsDb == null) {
        ConnectWeaponsDatabase();
        return;
    }

    int csTeam = GetClientTeam(client);
    char side[3];
    if (csTeam == CS_TEAM_T) {
        strcopy(side, sizeof(side), "T");
    } else if (csTeam == CS_TEAM_CT) {
        strcopy(side, sizeof(side), "CT");
    } else {
        QueryKgnsLoadout(client, steamId, altAttempt, force);
        return;
    }

    char escaped[64];
    g_hWeaponsDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);
    pack.WriteCell(force ? 1 : 0);

    char query[384];
    Format(
        query,
        sizeof(query),
        "SELECT weapon_id, paintkit, wear, seed, stattrak, stattrak_count, nametag, knife_index FROM %sclutch_team_loadout WHERE steamid='%s' AND team='%s'",
        g_sTablePrefix,
        escaped,
        side
    );
    g_hWeaponsDb.Query(T_TeamLoadoutCallback, query, pack);
}

public void T_TeamLoadoutCallback(Database database, DBResultSet results, const char[] error, DataPack pack) {
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
        LogError("[Clutch] team loadout query failed: %s", error);
        return;
    }

    bool hadRows = ApplyTeamLoadoutFromResults(client, results, force);
    if (g_cvDebug.BoolValue) {
        int csTeamDbg = GetClientTeam(client);
        char sideDbg[3] = "??";
        if (csTeamDbg == CS_TEAM_T) {
            strcopy(sideDbg, sizeof(sideDbg), "T");
        } else if (csTeamDbg == CS_TEAM_CT) {
            strcopy(sideDbg, sizeof(sideDbg), "CT");
        }
        LogMessage(
            "[Clutch] team loadout side=%s steam=%s had=%d for %N",
            sideDbg,
            steamId,
            hadRows ? 1 : 0,
            client
        );
    }
    if (!hadRows) {
        if (altAttempt == 0) {
            char altSteam[32];
            strcopy(altSteam, sizeof(altSteam), steamId);
            if (altSteam[6] == '1') {
                altSteam[6] = '0';
            } else if (altSteam[6] == '0') {
                altSteam[6] = '1';
            }
            QueryTeamLoadout(client, altSteam, 1, force);
            return;
        }

        PrepareTeamLoadoutCaches(client);
        if (!g_bLoggedMissingLoadout[client]) {
            LogMessage("[Clutch] Sem loadout web para %s (%N) — vanilla (sem fallback !ws)", steamId, client);
            g_bLoggedMissingLoadout[client] = true;
        }
        QueryPlayerGloves(client, steamId, 0);
        ScheduleWeaponsAfterGlovesApply(client, force, !force);
        return;
    }

    g_bLoggedMissingLoadout[client] = false;
    QueryPlayerGloves(client, steamId, 0);
    ScheduleWeaponsAfterGlovesApply(client, force, !force);
}

bool ApplyTeamLoadoutFromResults(int client, DBResultSet results, bool force) {
    PrepareTeamLoadoutCaches(client);

    char knifeClass[64];
    knifeClass[0] = '\0';
    int knifePaintkit = 0;
    float knifeWear = 0.15;
    int knifeSeed = 0;
    int knifeTrak = 0;
    int knifeTrakCount = 0;
    char knifeTag[64];
    knifeTag[0] = '\0';

    bool any = false;

    while (results.FetchRow()) {
        any = true;

        char weaponId[64];
        DbFetchString(results, "weapon_id", weaponId, sizeof(weaponId));

        int paintkit = DbFetchInt(results, "paintkit", 0);
        if (paintkit <= 0) {
            continue;
        }

        float wear = DbFetchFloat(results, "wear", 0.15);
        if (wear <= 0.0) {
            wear = 0.15;
        }
        int seed = DbFetchInt(results, "seed", 0);
        int stattrak = DbFetchInt(results, "stattrak", 0);
        int stattrakCount = DbFetchInt(results, "stattrak_count", 0);
        char nametag[64];
        DbFetchString(results, "nametag", nametag, sizeof(nametag));
        int knifeIdx = DbFetchInt(results, "knife_index", -1);

        if (IsMeleeWeaponKey(weaponId)) {
            knifePaintkit = paintkit;
            knifeWear = wear;
            knifeSeed = seed;
            knifeTrak = stattrak;
            knifeTrakCount = stattrakCount;
            strcopy(knifeTag, sizeof(knifeTag), nametag);
            if (knifeIdx >= 0) {
                KnifeClassFromIndex(knifeIdx, knifeClass, sizeof(knifeClass));
            }
            if (knifeClass[0] == '\0') {
                strcopy(knifeClass, sizeof(knifeClass), weaponId);
            }
            continue;
        }

        int idx = GetClutchIndexForWeaponId(weaponId);
        if (idx < 0) {
            continue;
        }

        UpdateSlotCache(client, idx, paintkit, wear, seed, stattrak, stattrakCount, nametag);

        int weapon = FindPlayerWeapon(client, weaponId);
        if (weapon != -1) {
            ApplyCachedSkinToEntity(client, weapon, idx, false, true, force);
        } else if (force) {
            ClutchGiveCachedWeapon(client, idx);
        } else if (g_cvDebug.BoolValue) {
            LogMessage(
                "[Clutch] Cached %s paintkit %d for %N (pick up weapon to apply)",
                weaponId,
                paintkit,
                client
            );
        }
    }

    if (!any) {
        return false;
    }

    if (knifePaintkit > 0 && knifeClass[0] != '\0') {
        strcopy(g_CachedKnifeClass[client], CLUTCH_KNIFE_CLASS_LEN, knifeClass);
#if defined _weapons_included_
        if (force) {
            RefreshWeaponsReloadNativeFlag();
            TryReloadWeaponsPluginData(client);
        }
#endif
        ClutchSetClientKnife(client, knifeClass);

        int knifeWeapon = FindPlayerWeapon(client, knifeClass);
        if (knifeWeapon != -1) {
            SetClutchWeaponProps(client, knifeWeapon, knifePaintkit, knifeWear, knifeSeed, knifeTrak, knifeTrakCount, knifeTag, true);
        }

        DataPack knifePack = new DataPack();
        knifePack.WriteCell(GetClientUserId(client));
        knifePack.WriteString(knifeClass);
        knifePack.WriteCell(knifePaintkit);
        knifePack.WriteFloat(knifeWear);
        knifePack.WriteCell(knifeSeed);
        knifePack.WriteCell(knifeTrak);
        knifePack.WriteCell(knifeTrakCount);
        knifePack.WriteString(knifeTag);
        CreateTimer(0.35, Timer_ApplyKnifeSkinDelayed, knifePack, TIMER_FLAG_NO_MAPCHANGE);
        int useridKnife = GetClientUserId(client);
        CreateTimer(0.75, Timer_ApplyKnifeSkinFromCache, useridKnife, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(1.5, Timer_ApplyKnifeSkinFromCache, useridKnife, TIMER_FLAG_NO_MAPCHANGE);
    }

    bool allowRegive = g_bAllowWeaponRegive[client];
    if (allowRegive) {
        g_bAllowWeaponRegive[client] = false;
    }
    ScheduleForceReapply(client, force, allowRegive);
    return true;
}

void QueryPlayerLoadout(int client, const char[] steamId, int altAttempt, bool force = false) {
    QueryTeamLoadout(client, steamId, altAttempt, force);
}

void QueryPlayerStickers(int client, const char[] steamId, int altAttempt) {
    if (g_hStickersDb == null) {
        ConnectStickersDatabase();
        ScheduleStickersQueryRetry(client, steamId, altAttempt, 0.5);
        return;
    }

    if (!g_bStickersTableReady) {
        EnsureClutchStickersTable();
    }

    char escaped[64];
    g_hStickersDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);

    char query[384];
    Format(
        query,
        sizeof(query),
        "SELECT weaponindex, team, slot0, slot1, slot2, slot3, slot4, slot5, wear0, wear1, wear2, wear3, wear4, wear5 FROM %s WHERE steamid='%s'",
        g_sStickersTable,
        escaped
    );
    g_hStickersDb.Query(T_StickersCallback, query, pack);
}

void QueryLegacyPlayerStickers(int client, const char[] steamId, int altAttempt) {
    if (g_hStickersDb == null) {
        return;
    }

    char escaped[64];
    g_hStickersDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);

    char query[384];
    Format(
        query,
        sizeof(query),
        "SELECT weaponindex, slot0, slot1, slot2, slot3, slot4, slot5, wear0, wear1, wear2, wear3, wear4, wear5 FROM %s WHERE steamid='%s'",
        g_sLegacyStickersTable,
        escaped
    );
    g_hStickersDb.Query(T_LegacyStickersCallback, query, pack);
}

void ClutchCacheStickerRowForTeam(
    int client,
    int defIndex,
    int teamSlot,
    DBResultSet results,
    int slotColumnStart,
    int wearColumnStart
) {
    int idx = ClutchIndexFromDefIndex(defIndex);
    if (idx < 0 || IsMeleeWeaponKey(g_ClutchWeaponKeys[idx])) {
        return;
    }

    for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
        g_iStickerSlots[client][teamSlot][idx][s] = results.FetchInt(slotColumnStart + s);
        if (wearColumnStart >= 0) {
            g_fStickerWears[client][teamSlot][idx][s] = results.FetchFloat(wearColumnStart + s);
        } else {
            g_fStickerWears[client][teamSlot][idx][s] = 0.0;
        }
    }
}

void ScheduleStickersQueryRetry(int client, const char[] steamId, int altAttempt, float delay) {
    DataPack retry = new DataPack();
    retry.WriteCell(GetClientUserId(client));
    retry.WriteString(steamId);
    retry.WriteCell(altAttempt);
    CreateTimer(delay, Timer_RetryStickersQuery, retry, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RetryStickersQuery(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int altAttempt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    QueryPlayerStickers(client, steamId, altAttempt);
    return Plugin_Stop;
}

public void T_StickersCallback(Database database, DBResultSet results, const char[] error, DataPack pack) {
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
        LogError("[Clutch] stickers DB query failed: %s", error);
        if (StrContains(error, "no such table", false) != -1) {
            EnsureClutchStickersTable();
            ScheduleStickersQueryRetry(client, steamId, altAttempt, 0.5);
        }
        return;
    }

    bool anyRow = false;
    while (results.FetchRow()) {
        if (!anyRow) {
            ClutchClearStickerCache(client);
            anyRow = true;
        }
        int defIndex = results.FetchInt(0);
        char teamLabel[4];
        results.FetchString(1, teamLabel, sizeof(teamLabel));
        int teamSlot = StrEqual(teamLabel, "CT", false) ? 1 : 0;
        ClutchCacheStickerRowForTeam(client, defIndex, teamSlot, results, 2, 8);

        if (g_cvDebug.BoolValue) {
            int idx = ClutchIndexFromDefIndex(defIndex);
            if (idx >= 0) {
                LogMessage(
                    "[Clutch] Cached stickers %s defindex %d (%s) slots %d,%d,%d,%d,%d for %N",
                    teamLabel,
                    defIndex,
                    g_ClutchWeaponKeys[idx],
                    g_iStickerSlots[client][teamSlot][idx][0],
                    g_iStickerSlots[client][teamSlot][idx][1],
                    g_iStickerSlots[client][teamSlot][idx][2],
                    g_iStickerSlots[client][teamSlot][idx][3],
                    g_iStickerSlots[client][teamSlot][idx][4],
                    client
                );
            }
        }
    }

    if (!anyRow) {
        if (altAttempt == 0) {
            if (steamId[6] == '1') {
                steamId[6] = '0';
            } else if (steamId[6] == '0') {
                steamId[6] = '1';
            }
            QueryPlayerStickers(client, steamId, 1);
            return;
        }

        LogError(
            "[Clutch] no %s rows for steam %s (db=%s) — save stickers on site / check STICKERS_DB_PATH",
            g_sStickersTable,
            steamId,
            g_sResolvedStickersDbPath
        );
        return;
    }

    ClutchReapplyStickersOnPlayerWeapons(client);
}

public void T_LegacyStickersCallback(Database database, DBResultSet results, const char[] error, DataPack pack) {
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
        LogError("[Clutch] legacy stickers DB query failed: %s", error);
        return;
    }

    bool anyRow = false;
    while (results.FetchRow()) {
        anyRow = true;
        int defIndex = results.FetchInt(0);
        int slots[CLUTCH_STICKER_SLOTS];
        float wears[CLUTCH_STICKER_SLOTS];
        for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
            slots[s] = results.FetchInt(1 + s);
            wears[s] = results.FetchFloat(1 + CLUTCH_STICKER_SLOTS + s);
        }

        int idx = ClutchIndexFromDefIndex(defIndex);
        if (idx < 0 || IsMeleeWeaponKey(g_ClutchWeaponKeys[idx])) {
            continue;
        }

        for (int teamSlot = 0; teamSlot < 1; teamSlot++) {
            for (int s = 0; s < CLUTCH_STICKER_SLOTS; s++) {
                g_iStickerSlots[client][teamSlot][idx][s] = slots[s];
                g_fStickerWears[client][teamSlot][idx][s] = wears[s];
            }
        }

        if (g_cvDebug.BoolValue) {
            LogMessage(
                "[Clutch] Cached legacy stickers defindex %d (%s) slots %d,%d,%d,%d,%d for %N (TR only)",
                defIndex,
                g_ClutchWeaponKeys[idx],
                slots[0],
                slots[1],
                slots[2],
                slots[3],
                slots[4],
                client
            );
        }
    }

    if (!anyRow) {
        if (altAttempt == 0) {
            if (steamId[6] == '1') {
                steamId[6] = '0';
            } else if (steamId[6] == '0') {
                steamId[6] = '1';
            }
            QueryLegacyPlayerStickers(client, steamId, 1);
            return;
        }

        return;
    }

    LogMessage("[Clutch] Applied stickers from legacy %s for %N (TR only — save CT stickers on site)", g_sLegacyStickersTable, client);
    ClutchReapplyStickersOnPlayerWeapons(client);
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
            QueryKgnsLoadout(client, steamId, 1, force);
            return;
        }

        if (!g_bLoggedMissingLoadout[client]) {
            LogMessage("[Clutch] Sem loadout no DB para %s (%N)", steamId, client);
            g_bLoggedMissingLoadout[client] = true;
        }
        return;
    }

    g_bLoggedMissingLoadout[client] = false;
    ApplyLoadoutFromDbRow(client, results, force);
}

void QueryPlayerGloves(int client, const char[] steamId, int altAttempt) {
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        ClutchGlovesRefreshClientSafe(client);
        if (IsPlayerAlive(client)) {
            CreateTimer(0.25, Timer_ApplyGlovesAfterRefresh, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        }
        return;
    }
#endif
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
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        if (g_bGlovesNativeReady) {
            return ClutchGlovesIsClientUsingSafe(client);
        }
        return false;
    }
#endif
    return g_iLastGloveGroup[client] > 0 && g_iLastGlovePaint[client] > 0;
}

void ClutchRequestClientModelUpdate(int client) {
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        return;
    }
#endif
    if (!ClutchShouldUpdateClientModel(client)) {
        ClutchEnforceGloveState(client);
        return;
    }
    CS_UpdateClientModel(client);
}

void ClutchEnableGloveThink(int client) {
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        return;
    }
#endif
#if defined _clutch_gloves_included_
    if (g_bGlovesNativeReady) {
        return;
    }
#endif
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
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        return;
    }
#endif
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
        if (ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
            QueryPlayerGloves(client, steamId, 0);
        }
    }
    return Plugin_Stop;
}

void ClutchGivePlayerGloves(int client, int group, int paintkit, float wear) {
#if defined _clutch_gloves_included_
    if (ClutchUseExternalGlovesPlugin()) {
        return;
    }
#endif
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
    if (worldModel) {
        SetEntProp(client, Prop_Send, "m_nBody", 1);
    }

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
        "[Clutch] Applied gloves group %d paintkit %d for %N (world_model=%d)",
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
    int csTeam = GetClientTeam(client);

    for (int i = 0; i < CLUTCH_WEAPON_SLOTS; i++) {
        char weaponKey[32];
        strcopy(weaponKey, sizeof(weaponKey), g_ClutchWeaponKeys[i]);

        if (!ClutchWeaponAllowedForTeam(weaponKey, csTeam)) {
            continue;
        }

        // Knives + shared guns: clutch_team_loadout only (kgns row may hold CT paints).
        if (IsMeleeWeaponKey(weaponKey) || ClutchIsSharedWeaponKey(weaponKey)) {
            continue;
        }

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
            ApplyCachedSkinToEntity(client, weapon, i, false, force);
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

    bool allowRegive = g_bAllowWeaponRegive[client];
    if (allowRegive) {
        g_bAllowWeaponRegive[client] = false;
    }
    ScheduleForceReapply(client, force, allowRegive);
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

    if (ClutchRoutineFullApplyBlocked(client, force)) {
        return;
    }

    if (
        !force
        && g_bPendingWebLoadout[client]
        && ClutchIsLiveMatch()
        && !ClutchClientIsSkinAdmin(client)
    ) {
        return;
    }

    float now = GetGameTime();
    if (!force && (now - g_fLastApplyTime[client]) < APPLY_COOLDOWN_SECONDS) {
        return;
    }
    g_fLastApplyTime[client] = now;

    if (
        force
        && !g_bAllowWeaponRegive[client]
        && g_cvOncePerMatch.BoolValue
        && IsPlayerAlive(client)
    ) {
        g_bMatchLoadoutSynced[client] = true;
    }

    char steamId[32];
    if (!ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
        return;
    }

    QueryPlayerLoadout(client, steamId, 0, force);
    QueryPlayerStickers(client, steamId, 0);
}

#if defined _clutch_gloves_included_
public void ClutchGloves_OnClientApplied(int client, int group, int paintkit) {
    if (client <= 0 || IsFakeClient(client) || group <= 0 || paintkit <= 0) {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(0.3, Timer_ApplyWeaponsAfterGloves, pack, TIMER_FLAG_NO_MAPCHANGE);
}
#endif
