#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <clutch_steam>

#define PLUGIN_VERSION "1.4.0"
#define GLOVE_THINK_TICK_MOD 8

ConVar g_cvDb;
ConVar g_cvTablePrefix;
ConVar g_cvWorldModel;
ConVar g_cvForceBody;
ConVar g_cvDebug;

Database g_hDb = null;
char g_sTablePrefix[16];
char g_sDbName[64];

Handle g_hForwardApplied = null;

int g_iGroup[MAXPLAYERS + 1][4];
int g_iPaint[MAXPLAYERS + 1][4];
float g_fWear[MAXPLAYERS + 1][4];
bool g_bThinkHooked[MAXPLAYERS + 1];

public Plugin myinfo = {
    name = "Clutch Gloves",
    author = "clutchclube",
    description = "kgns-style gloves from SQLite (site sync) — load before z_clutch_skins_bridge",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    CreateNative("ClutchGloves_RefreshClient", Native_RefreshClient);
    CreateNative("ClutchGloves_ApplyClient", Native_ApplyClient);
    CreateNative("ClutchGloves_IsClientUsingGloves", Native_IsUsing);
    g_hForwardApplied = CreateGlobalForward(
        "ClutchGloves_OnClientApplied",
        ET_Ignore,
        Param_Cell,
        Param_Cell,
        Param_Cell
    );
    RegPluginLibrary("clutch_gloves");
    return APLRes_Success;
}

public void OnPluginStart() {
    g_cvDb = CreateConVar(
        "clutch_gloves_db",
        "storage-local",
        "Database connection (databases.cfg) — same as clutch_weapons_db",
        FCVAR_NOTIFY
    );
    g_cvTablePrefix = CreateConVar(
        "clutch_gloves_table_prefix",
        "",
        "Table prefix — same as clutch_weapons_table_prefix",
        FCVAR_NOTIFY
    );
    g_cvWorldModel = CreateConVar(
        "clutch_gloves_world_model",
        "0",
        "0 = kgns view-only (no m_hMoveParent). 1 = others see gloves on player model",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );
    g_cvForceBody = CreateConVar(
        "clutch_gloves_force_body",
        "1",
        "1 = m_nBody=1 hides default glove mesh (required on CS:GO Legacy). 0 = kgns vanilla",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );
    g_cvDebug = CreateConVar("clutch_gloves_debug", "0", "Log glove apply", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "clutch_gloves");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
    RegAdminCmd("sm_clutch_gloves_refresh", Command_Refresh, ADMFLAG_ROOT, "Re-read gloves DB into cache (visual apply on spawn)");
    RegAdminCmd("sm_clutch_gloves_apply", Command_Apply, ADMFLAG_ROOT, "Apply gloves from cache (no DB)");
    RegAdminCmd("sm_clutch_gloves_status", Command_Status, ADMFLAG_ROOT, "Dump glove cache / wearable state");

    ConnectDatabase();
    LogMessage("[ClutchGloves] Plugin loaded v%s", PLUGIN_VERSION);
}

public void OnAllPluginsLoaded() {
    SyncSharedConVars();
    ConnectDatabase();
}

void SyncSharedConVars() {
    ConVar cvDb = FindConVar("clutch_weapons_db");
    if (cvDb != null) {
        cvDb.GetString(g_sDbName, sizeof(g_sDbName));
        if (g_sDbName[0] != '\0') {
            g_cvDb.SetString(g_sDbName);
        }
    } else {
        g_cvDb.GetString(g_sDbName, sizeof(g_sDbName));
    }

    ConVar cvPrefix = FindConVar("clutch_weapons_table_prefix");
    if (cvPrefix != null) {
        cvPrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));
        g_cvTablePrefix.SetString(g_sTablePrefix);
    } else {
        g_cvTablePrefix.GetString(g_sTablePrefix, sizeof(g_sTablePrefix));
    }
}

public void OnConfigsExecuted() {
    SyncSharedConVars();
    ConnectDatabase();
}

public void OnClientDisconnect(int client) {
    DisableGloveThink(client);
    for (int team = 0; team < 4; team++) {
        g_iGroup[client][team] = 0;
        g_iPaint[client][team] = 0;
        g_fWear[client][team] = 0.0;
    }
}

public void OnClientPostAdminCheck(int client) {
    if (IsFakeClient(client)) {
        return;
    }
    RefreshClientFromDatabase(client, 0);
}

public void OnClientAuthorized(int client, const char[] authString) {
    if (IsFakeClient(client)) {
        return;
    }
    RefreshClientFromDatabase(client, 0);
}

void ConnectDatabase() {
    SyncSharedConVars();

    if (g_hDb != null) {
        delete g_hDb;
        g_hDb = null;
    }

    if (g_sDbName[0] == '\0') {
        g_cvDb.GetString(g_sDbName, sizeof(g_sDbName));
    }

    Database.Connect(OnDatabaseConnected, g_sDbName);
}

public void OnDatabaseConnected(Database database, const char[] error, any data) {
    if (database == null) {
        LogError("[ClutchGloves] DB connect failed: %s", error);
        return;
    }
    g_hDb = database;
    EnsureGlovesTable();
}

void EnsureGlovesTable() {
    if (g_hDb == null) {
        return;
    }

    char query[512];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %sgloves (steamid varchar(32) NOT NULL PRIMARY KEY, t_group int(5) NOT NULL DEFAULT 0, t_glove int(5) NOT NULL DEFAULT 0, t_float decimal(3,2) NOT NULL DEFAULT 0.0, ct_group int(5) NOT NULL DEFAULT 0, ct_glove int(5) NOT NULL DEFAULT 0, ct_float decimal(3,2) NOT NULL DEFAULT 0.0)",
        g_sTablePrefix
    );
    g_hDb.Query(OnEnsureTable, query);
}

public void OnEnsureTable(Database database, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("[ClutchGloves] gloves table create failed: %s", error);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || IsFakeClient(client)) {
        return;
    }

    GivePlayerGloves(client);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(0.5, Timer_RetryAfterTeam, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RetryAfterTeam(Handle timer, DataPack pack) {
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
        GivePlayerGloves(client);
    }
    return Plugin_Stop;
}

public Action Command_Refresh(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            RefreshClientFromDatabase(i, 0);
        }
    }
    return Plugin_Handled;
}

public Action Command_Status(int client, int args) {
    LogMessage("[ClutchGloves] db=%s prefix=%s connected=%d", g_sDbName, g_sTablePrefix, g_hDb != null);

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }

        char steamId[32];
        if (!ClutchGetClientSteam2(i, steamId, sizeof(steamId))) {
            strcopy(steamId, sizeof(steamId), "auth-pending");
        }

        int team = GetClientTeam(i);
        int wearable = GetEntPropEnt(i, Prop_Send, "m_hMyWearables");
        int body = GetEntProp(i, Prop_Send, "m_nBody");
        int wGroup = 0;
        int wPaint = 0;

        if (wearable != -1 && IsValidEntity(wearable)) {
            wGroup = GetEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex");
            wPaint = GetEntProp(wearable, Prop_Send, "m_nFallbackPaintKit");
        }

        LogMessage(
            "[ClutchGloves] %N steam=%s team=%d alive=%d body=%d cache T=%d/%d CT=%d/%d wearable=%d def=%d paint=%d",
            i,
            steamId,
            team,
            IsPlayerAlive(i) ? 1 : 0,
            body,
            g_iGroup[i][CS_TEAM_T],
            g_iPaint[i][CS_TEAM_T],
            g_iGroup[i][CS_TEAM_CT],
            g_iPaint[i][CS_TEAM_CT],
            wearable,
            wGroup,
            wPaint
        );
    }
    return Plugin_Handled;
}

public Action Command_Apply(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            GivePlayerGloves(i);
        }
    }
    return Plugin_Handled;
}

public int Native_ApplyClient(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients) {
        return 0;
    }
    GivePlayerGloves(client);
    return 0;
}

public int Native_RefreshClient(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients) {
        return 0;
    }
    RefreshClientFromDatabase(client, 0);
    return 0;
}

public int Native_IsUsing(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients) {
        return 0;
    }
    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        return 0;
    }
    return g_iPaint[client][team] > 0 ? 1 : 0;
}

void RefreshClientFromDatabase(int client, int altAttempt) {
    if (!IsClientInGame(client) || IsFakeClient(client) || g_hDb == null) {
        return;
    }

    char steamId[32];
    if (!ClutchGetClientSteam2(client, steamId, sizeof(steamId))) {
        return;
    }

    char escaped[64];
    g_hDb.Escape(steamId, escaped, sizeof(escaped));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteCell(altAttempt);

    char query[256];
    Format(
        query,
        sizeof(query),
        "SELECT * FROM %sgloves WHERE steamid='%s' LIMIT 1",
        g_sTablePrefix,
        escaped
    );
    g_hDb.Query(OnQueryGloves, query, pack);
}

public void OnQueryGloves(Database database, DBResultSet results, const char[] error, DataPack pack) {
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
        LogError("[ClutchGloves] query failed: %s", error);
        return;
    }

    if (!results.FetchRow()) {
        if (altAttempt == 0) {
            if (steamId[6] == '1') {
                steamId[6] = '0';
            } else if (steamId[6] == '0') {
                steamId[6] = '1';
            }
            RefreshClientFromDatabase(client, 1);
        }
        return;
    }

    LoadGloveRow(client, results);
    if (g_cvDebug.BoolValue) {
        LogMessage(
            "[ClutchGloves] DB row %N T=%d/%d CT=%d/%d",
            client,
            g_iGroup[client][CS_TEAM_T],
            g_iPaint[client][CS_TEAM_T],
            g_iGroup[client][CS_TEAM_CT],
            g_iPaint[client][CS_TEAM_CT]
        );
    }
    LogMessage("[ClutchGloves] Cache updated for %N — visual apply on next spawn", client);
}

void LoadGloveRow(int client, DBResultSet results) {
    int tGroup = DbInt(results, "t_group", 0);
    int tPaint = DbInt(results, "t_glove", 0);
    float tWear = DbFloat(results, "t_float", 0.15);

    int ctGroup = DbInt(results, "ct_group", 0);
    int ctPaint = DbInt(results, "ct_glove", 0);
    float ctWear = DbFloat(results, "ct_float", 0.15);

    if (ctPaint <= 0 && tPaint > 0) {
        ctGroup = tGroup;
        ctPaint = tPaint;
        ctWear = tWear;
    }
    if (tPaint <= 0 && ctPaint > 0) {
        tGroup = ctGroup;
        tPaint = ctPaint;
        tWear = ctWear;
    }

    g_iGroup[client][CS_TEAM_T] = tGroup;
    g_iPaint[client][CS_TEAM_T] = tPaint;
    g_fWear[client][CS_TEAM_T] = tWear;

    g_iGroup[client][CS_TEAM_CT] = ctGroup;
    g_iPaint[client][CS_TEAM_CT] = ctPaint;
    g_fWear[client][CS_TEAM_CT] = ctWear;
}

int DbInt(DBResultSet results, const char[] column, int defaultValue) {
    int field = -1;
    if (!results.FieldNameToNum(column, field)) {
        return defaultValue;
    }
    return results.FetchInt(field);
}

float DbFloat(DBResultSet results, const char[] column, float defaultValue) {
    int field = -1;
    if (!results.FieldNameToNum(column, field)) {
        return defaultValue;
    }
    return results.FetchFloat(field);
}

void EnforceGloveBody(int client) {
    if (g_cvForceBody.BoolValue || g_cvWorldModel.BoolValue) {
        SetEntProp(client, Prop_Send, "m_nBody", 1);
    }
}

void ClearGloveBody(int client) {
    if (g_cvForceBody.BoolValue || g_cvWorldModel.BoolValue) {
        SetEntProp(client, Prop_Send, "m_nBody", 0);
    }
}

void FixCustomArms(int client) {
    char armsModel[2];
    GetEntPropString(client, Prop_Send, "m_szArmsModel", armsModel, sizeof(armsModel));
    if (armsModel[0]) {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", "");
    }
}

void EnableGloveThink(int client) {
    if (client <= 0 || IsFakeClient(client) || g_bThinkHooked[client]) {
        return;
    }
    SDKHook(client, SDKHook_PreThink, OnGlovePreThink);
    g_bThinkHooked[client] = true;
}

void DisableGloveThink(int client) {
    if (client <= 0 || !g_bThinkHooked[client]) {
        return;
    }
    SDKUnhook(client, SDKHook_PreThink, OnGlovePreThink);
    g_bThinkHooked[client] = false;
}

public void OnGlovePreThink(int client) {
    if (!IsPlayerAlive(client)) {
        return;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT || g_iPaint[client][team] <= 0) {
        return;
    }

    if ((GetGameTickCount() % GLOVE_THINK_TICK_MOD) != (client % GLOVE_THINK_TICK_MOD)) {
        return;
    }

    FixCustomArms(client);
    EnforceGloveBody(client);
}

void ScrubStrayWearables(int client, int keepEnt) {
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "wearable_item")) != -1) {
        if (!IsValidEntity(entity)) {
            continue;
        }
        if (GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") == client && entity != keepEnt) {
            AcceptEntityInput(entity, "KillHierarchy");
            if (IsValidEntity(entity)) {
                RemoveEntity(entity);
            }
        }
    }
}

void DestroyPlayerWearables(int client) {
    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", -1);

    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "wearable_item")) != -1) {
        if (!IsValidEntity(entity)) {
            continue;
        }
        if (GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") != client) {
            continue;
        }
        SetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity", -1);
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

    ClearGloveBody(client);
    FixCustomArms(client);
}

void NetworkUpdate(int entity) {
    int offset = FindSendPropInfo("CBaseEntity", "m_nModelIndex");
    if (offset != -1) {
        ChangeEdictState(entity, offset);
    }
}

void GivePlayerGloves(int client) {
    if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client)) {
        return;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
        return;
    }

    int group = g_iGroup[client][team];
    int paint = g_iPaint[client][team];
    bool worldModel = g_cvWorldModel.BoolValue;

    if (group <= 0 || paint <= 0) {
        DestroyPlayerWearables(client);
        DisableGloveThink(client);
        return;
    }

    int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
    if (ent != -1 && IsValidEntity(ent)) {
        int existingGroup = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");
        int existingPaint = GetEntProp(ent, Prop_Send, "m_nFallbackPaintKit");
        if (existingGroup == group && existingPaint == paint) {
            FixCustomArms(client);
            ScrubStrayWearables(client, ent);
            EnforceGloveBody(client);
            NetworkUpdate(ent);
            EnableGloveThink(client);
            return;
        }
    }

    DestroyPlayerWearables(client);

    ent = CreateEntityByName("wearable_item");
    if (ent == -1) {
        LogError("[ClutchGloves] CreateEntityByName(wearable_item) failed for %N", client);
        return;
    }

    float wear = g_fWear[client][team];
    if (wear <= 0.0) {
        wear = 0.0001;
    } else if (wear >= 1.0) {
        wear = 0.999999;
    }

    SetEntProp(ent, Prop_Send, "m_iItemIDLow", -1);
    SetEntProp(ent, Prop_Send, "m_iItemIDHigh", -1);
    SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", group);
    SetEntProp(ent, Prop_Send, "m_nFallbackPaintKit", paint);
    SetEntPropFloat(ent, Prop_Send, "m_flFallbackWear", wear);
    SetEntProp(ent, Prop_Send, "m_nFallbackSeed", GetRandomInt(1, 1000));
    SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", client);
    SetEntPropEnt(ent, Prop_Data, "m_hParent", client);
    if (worldModel) {
        SetEntPropEnt(ent, Prop_Data, "m_hMoveParent", client);
    }
    SetEntProp(ent, Prop_Send, "m_bInitialized", 1);

    DispatchSpawn(ent);

    SetEntPropEnt(client, Prop_Send, "m_hMyWearables", ent);
    EnforceGloveBody(client);

    ScrubStrayWearables(client, ent);
    NetworkUpdate(ent);
    EnableGloveThink(client);

    LogMessage(
        "[ClutchGloves] Applied group %d paintkit %d for %N (team %d world=%d force_body=%d)",
        group,
        paint,
        client,
        team,
        worldModel ? 1 : 0,
        g_cvForceBody.BoolValue ? 1 : 0
    );

    if (g_hForwardApplied != null) {
        Call_StartForward(g_hForwardApplied);
        Call_PushCell(client);
        Call_PushCell(group);
        Call_PushCell(paint);
        Call_Finish();
    }
}
