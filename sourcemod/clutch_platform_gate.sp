#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"
#define TABLE_ALLOWLIST "clutch_steam_allowlist"

Database g_hDb = null;
char g_sDbName[64] = "storage-local";
ConVar g_cvEnabled = null;

public Plugin myinfo = {
    name = "Clutch Platform Gate",
    author = "clutchclube",
    description = "Kick players without a clutchclube.com.br account linked to Steam",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com.br"
};

public void OnPluginStart() {
    CreateConVar("clutch_platform_gate_version", PLUGIN_VERSION, "Clutch platform gate version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

    g_cvEnabled = CreateConVar(
        "clutch_platform_gate_enabled",
        "1",
        "Kick players whose Steam is not registered on clutchclube.com.br",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );

    ConVar cvDb = CreateConVar(
        "clutch_platform_gate_db",
        "storage-local",
        "Database connection (databases.cfg) — same SQLite as weapons sync",
        FCVAR_NONE
    );
    cvDb.GetString(g_sDbName, sizeof(g_sDbName));

    ConnectDatabase();

    RegAdminCmd("sm_clutch_gate_check", Cmd_Check, ADMFLAG_GENERIC, "Check if a player is on the platform allowlist");
}

public void OnPluginEnd() {
    if (g_hDb != null) {
        delete g_hDb;
        g_hDb = null;
    }
}

public void OnClientAuthorized(int client, const char[] auth) {
    if (!g_cvEnabled.BoolValue || IsFakeClient(client)) {
        return;
    }

    int accountId = GetSteamAccountID(client, AuthIdType_AccountID);
    if (accountId <= 0) {
        KickClient(client, "Steam não identificado. Abra o Steam e tente novamente.");
        return;
    }

    if (!IsAccountAllowed(accountId)) {
        KickClient(
            client,
            "Conta não vinculada ao Clutch Clube. Cadastre-se em clutchclube.com.br e vincule sua Steam."
        );
    }
}

public Action Cmd_Check(int client, int args) {
    int target = client;
    if (args >= 1) {
        char arg[32];
        GetCmdArg(1, arg, sizeof(arg));
        target = FindTarget(client, arg, true, false);
        if (target == -1) {
            return Plugin_Handled;
        }
    }

    if (target == 0) {
        ReplyToCommand(client, "[ClutchGate] Usage: sm_clutch_gate_check <player>");
        return Plugin_Handled;
    }

    int accountId = GetSteamAccountID(target, AuthIdType_AccountID);
    bool allowed = IsAccountAllowed(accountId);
    char name[MAX_NAME_LENGTH];
    GetClientName(target, name, sizeof(name));
    ReplyToCommand(
        client,
        "[ClutchGate] %s account_id=%d allowed=%s",
        name,
        accountId,
        allowed ? "yes" : "no"
    );
    return Plugin_Handled;
}

bool IsAccountAllowed(int accountId) {
    if (accountId <= 0) {
        return false;
    }

    if (g_hDb == null) {
        ConnectDatabase();
        if (g_hDb == null) {
            LogError("[ClutchGate] DB unavailable — denying connection");
            return false;
        }
    }

    char query[160];
    Format(query, sizeof(query), "SELECT 1 FROM %s WHERE account_id = %d LIMIT 1", TABLE_ALLOWLIST, accountId);

    DBResultSet results = SQL_Query(g_hDb, query);
    if (results == null) {
        char err[256];
        SQL_GetError(g_hDb, err, sizeof(err));
        LogError("[ClutchGate] query failed: %s", err);
        return false;
    }

    bool found = results.FetchRow();
    delete results;
    return found;
}

void ConnectDatabase() {
    if (g_hDb != null) {
        delete g_hDb;
        g_hDb = null;
    }

    char error[256];
    g_hDb = SQLite_UseDatabase(g_sDbName, error, sizeof(error));
    if (g_hDb == null) {
        LogError("[ClutchGate] DB connect failed: %s", error);
        return;
    }

    EnsureTable();
}

void EnsureTable() {
    char query[192];
    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s (account_id INTEGER PRIMARY KEY NOT NULL)",
        TABLE_ALLOWLIST
    );

    if (!SQL_FastQuery(g_hDb, query)) {
        char err[256];
        SQL_GetError(g_hDb, err, sizeof(err));
        LogError("[ClutchGate] create table failed: %s", err);
    }
}
