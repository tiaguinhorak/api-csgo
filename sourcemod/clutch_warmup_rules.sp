#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"
#define MAX_SPAWN_POINTS 256

ConVar g_cvEnabled;
ConVar g_cvWarmupMoney;
ConVar g_cvWarmupMaxMoney;
ConVar g_cvBuyAnywhere;
ConVar g_cvRandomSpawns;
ConVar g_cvDmRespawn;
ConVar g_cvRespawnDelay;

ConVar g_cvMpBuyAnywhere;
ConVar g_cvMpMaxMoney;
ConVar g_cvMpStartMoney;
ConVar g_cvMpBuyTime;

int g_iSpawnPoints[MAX_SPAWN_POINTS];
int g_iSpawnCount = 0;

bool g_bLiveApplied = false;

public Plugin myinfo = {
    name = "Clutch Warmup Rules",
    author = "Clutch",
    description = "Warmup-only economy/buy, random spawns and deathmatch respawn (admin-configurable).",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com"
};

public void OnPluginStart() {
    g_cvEnabled = CreateConVar("clutch_wr_enabled", "1", "Enable Clutch warmup rules.", _, true, 0.0, true, 1.0);
    g_cvWarmupMoney = CreateConVar("clutch_wr_warmup_money", "16000", "Money granted to players during warmup.", _, true, 0.0);
    g_cvWarmupMaxMoney = CreateConVar("clutch_wr_warmup_maxmoney", "16000", "Max money cap during warmup.", _, true, 0.0);
    g_cvBuyAnywhere = CreateConVar("clutch_wr_buy_anywhere", "1", "Allow buying anywhere/anytime during warmup.", _, true, 0.0, true, 1.0);
    g_cvRandomSpawns = CreateConVar("clutch_wr_random_spawns", "1", "Always spawn players at a random spawn point.", _, true, 0.0, true, 1.0);
    g_cvDmRespawn = CreateConVar("clutch_wr_dm_respawn", "0", "Deathmatch-style respawn on death.", _, true, 0.0, true, 1.0);
    g_cvRespawnDelay = CreateConVar("clutch_wr_respawn_delay", "2.0", "Respawn delay (seconds) for DM respawn.", _, true, 0.0);

    g_cvMpBuyAnywhere = FindConVar("mp_buy_anywhere");
    g_cvMpMaxMoney = FindConVar("mp_maxmoney");
    g_cvMpStartMoney = FindConVar("mp_startmoney");
    g_cvMpBuyTime = FindConVar("mp_buytime");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_Post);

    AutoExecConfig(true, "clutch_warmup_rules");
}

public void OnMapStart() {
    CacheSpawnPoints();
    g_bLiveApplied = false;
}

void CacheSpawnPoints() {
    g_iSpawnCount = 0;
    AddSpawnPointsByClass("info_player_terrorist");
    AddSpawnPointsByClass("info_player_counterterrorist");
}

void AddSpawnPointsByClass(const char[] classname) {
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, classname)) != -1) {
        if (g_iSpawnCount >= MAX_SPAWN_POINTS) {
            return;
        }
        if (IsValidEntity(ent)) {
            g_iSpawnPoints[g_iSpawnCount++] = ent;
        }
    }
}

bool IsWarmup() {
    return GameRules_GetProp("m_bWarmupPeriod") != 0;
}

public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    ApplyPhaseCvars();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    ApplyPhaseCvars();

    if (IsWarmup()) {
        for (int client = 1; client <= MaxClients; client++) {
            if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client)) {
                GiveWarmupMoney(client);
            }
        }
    }
}

/** Set economy/buy cvars according to warmup vs live phase. */
void ApplyPhaseCvars() {
    bool warmup = IsWarmup();

    if (warmup) {
        g_bLiveApplied = false;
        if (g_cvMpBuyAnywhere != null) {
            g_cvMpBuyAnywhere.SetInt(g_cvBuyAnywhere.BoolValue ? 1 : 0);
        }
        if (g_cvMpMaxMoney != null) {
            g_cvMpMaxMoney.SetInt(g_cvWarmupMaxMoney.IntValue);
        }
        if (g_cvMpStartMoney != null) {
            g_cvMpStartMoney.SetInt(g_cvWarmupMoney.IntValue);
        }
        if (g_cvBuyAnywhere.BoolValue && g_cvMpBuyTime != null) {
            g_cvMpBuyTime.SetInt(60000);
        }
    } else if (!g_bLiveApplied) {
        // Revert warmup-only economy/buy once the live match begins.
        g_bLiveApplied = true;
        if (g_cvMpBuyAnywhere != null) {
            g_cvMpBuyAnywhere.SetInt(0);
        }
        if (g_cvMpStartMoney != null) {
            g_cvMpStartMoney.SetInt(800);
        }
        if (g_cvMpMaxMoney != null) {
            g_cvMpMaxMoney.SetInt(16000);
        }
        if (g_cvMpBuyTime != null) {
            g_cvMpBuyTime.SetInt(20);
        }
    }
}

void GiveWarmupMoney(int client) {
    if (g_cvMpMaxMoney != null) {
        g_cvMpMaxMoney.SetInt(g_cvWarmupMaxMoney.IntValue);
    }
    SetEntProp(client, Prop_Send, "m_iAccount", g_cvWarmupMoney.IntValue);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    if (IsWarmup()) {
        GiveWarmupMoney(client);
    }

    if (g_cvRandomSpawns.BoolValue) {
        // Defer a frame so the engine finishes its own spawn placement first.
        RequestFrame(Frame_RandomSpawn, GetClientUserId(client));
    }
}

public void Frame_RandomSpawn(any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) {
        return;
    }
    if (g_iSpawnCount <= 0) {
        CacheSpawnPoints();
        if (g_iSpawnCount <= 0) {
            return;
        }
    }

    for (int attempt = 0; attempt < 5; attempt++) {
        int point = g_iSpawnPoints[GetRandomInt(0, g_iSpawnCount - 1)];
        if (!IsValidEntity(point)) {
            continue;
        }
        float origin[3];
        float angles[3];
        GetEntPropVector(point, Prop_Data, "m_vecOrigin", origin);
        GetEntPropVector(point, Prop_Data, "m_angRotation", angles);
        float vel[3];
        TeleportEntity(client, origin, angles, vel);
        return;
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnabled.BoolValue || !g_cvDmRespawn.BoolValue) {
        return;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    float delay = g_cvRespawnDelay.FloatValue;
    if (delay < 0.0) {
        delay = 0.0;
    }
    CreateTimer(delay, Timer_Respawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Respawn(Handle timer, any userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Stop;
    }
    int team = GetClientTeam(client);
    if ((team == CS_TEAM_T || team == CS_TEAM_CT) && !IsPlayerAlive(client)) {
        CS_RespawnPlayer(client);
    }
    return Plugin_Stop;
}
