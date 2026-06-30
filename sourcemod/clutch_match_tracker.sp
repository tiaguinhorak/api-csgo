#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "1.1.1"
#define TABLE_MATCH_LIVE "clutch_match_live"

Database g_hDb = null;
char g_sDbName[64] = "storage-local";

char g_sMatchId[64] = "";
char g_sPhase[16] = "idle";
int g_iScoreA = 0;
int g_iScoreB = 0;
int g_iRound = 0;
int g_iMaxRounds = 30;
int g_iStartedAt = 0;
int g_iFinishedAt = 0;
char g_sWinner[8] = "";

StringMap g_hRoster = null;
StringMap g_hStats = null;
ArrayList g_aDeaths = null;
ArrayList g_aRounds = null;
ArrayList g_aHighlights = null;

public Plugin myinfo = {
    name = "Clutch Match Tracker",
    author = "clutchclube",
    description = "Light ranked match stats via SQLite (round_end + match_over only)",
    version = PLUGIN_VERSION,
    url = "https://clutchclube.com.br"
};

public void OnPluginStart() {
    CreateConVar("clutch_match_tracker_version", PLUGIN_VERSION, "Clutch match tracker version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

    ConVar cvDb = CreateConVar(
        "clutch_match_db",
        "storage-local",
        "Database connection (databases.cfg) — same SQLite as weapons sync",
        FCVAR_NONE
    );
    cvDb.GetString(g_sDbName, sizeof(g_sDbName));

    g_hRoster = new StringMap();
    g_hStats = new StringMap();
    g_aDeaths = new ArrayList(512);
    g_aRounds = new ArrayList(64);
    g_aHighlights = new ArrayList(128);

    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("cs_win_panel_match", Event_MatchOver, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("round_mvp", Event_RoundMvp, EventHookMode_Post);

    RegServerCmd("clutch_match_begin", Cmd_MatchBegin, "Begin tracking a ranked match");
    RegServerCmd("clutch_match_roster", Cmd_MatchRoster, "Set team rosters (pipe-separated steam ids)");
    RegServerCmd("clutch_match_clear", Cmd_MatchClear, "Clear active match tracking");
    RegServerCmd("clutch_match_finish", Cmd_MatchFinish, "Finalize active match tracking (stats to DB)");

    ConnectDatabase();
}

public void OnPluginEnd() {
    delete g_hRoster;
    delete g_hStats;
    delete g_aDeaths;
    delete g_aRounds;
    delete g_aHighlights;
    if (g_hDb != null) {
        delete g_hDb;
        g_hDb = null;
    }
}

void ConnectDatabase() {
    if (g_hDb != null) {
        delete g_hDb;
        g_hDb = null;
    }

    char error[256];
    g_hDb = SQLite_UseDatabase(g_sDbName, error, sizeof(error));
    if (g_hDb == null) {
        LogError("[ClutchMatch] DB connect failed: %s", error);
        return;
    }

    char sql[] =
        "CREATE TABLE IF NOT EXISTS clutch_match_live ("
        ... "match_id VARCHAR(64) PRIMARY KEY NOT NULL,"
        ... "score_team_a INTEGER NOT NULL DEFAULT 0,"
        ... "score_team_b INTEGER NOT NULL DEFAULT 0,"
        ... "score_ct INTEGER NOT NULL DEFAULT 0,"
        ... "score_t INTEGER NOT NULL DEFAULT 0,"
        ... "round_num INTEGER NOT NULL DEFAULT 0,"
        ... "phase VARCHAR(16) NOT NULL DEFAULT 'idle',"
        ... "winner VARCHAR(8) NOT NULL DEFAULT '',"
        ... "max_rounds INTEGER NOT NULL DEFAULT 30,"
        ... "started_at INTEGER NOT NULL DEFAULT 0,"
        ... "finished_at INTEGER NOT NULL DEFAULT 0,"
        ... "stats_json TEXT NOT NULL DEFAULT '',"
        ... "updated_at INTEGER NOT NULL DEFAULT 0"
        ... ")";

    g_hDb.Query(EnsureTableCallback, sql);
}

public void EnsureTableCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (error[0]) {
        LogError("[ClutchMatch] ensure table: %s", error);
    }
}

public Action Cmd_MatchBegin(int args) {
    if (args < 1) {
        LogMessage("[ClutchMatch] usage: clutch_match_begin <matchId> [maxRounds]");
        return Plugin_Handled;
    }

    char matchId[64];
    GetCmdArg(1, matchId, sizeof(matchId));
    TrimString(matchId);
    if (strlen(matchId) < 4) {
        LogError("[ClutchMatch] invalid match id");
        return Plugin_Handled;
    }

    int maxRounds = 30;
    if (args >= 2) {
        char arg2[16];
        GetCmdArg(2, arg2, sizeof(arg2));
        maxRounds = StringToInt(arg2);
        if (maxRounds < 1) maxRounds = 30;
    }

    ResetMatchState();
    strcopy(g_sMatchId, sizeof(g_sMatchId), matchId);
    strcopy(g_sPhase, sizeof(g_sPhase), "warmup");
    g_iMaxRounds = maxRounds;
    g_iStartedAt = GetTime();
    g_iFinishedAt = 0;
    g_sWinner[0] = '\0';

    LogMessage("[ClutchMatch] begin %s maxRounds=%d", g_sMatchId, g_iMaxRounds);
    PersistLiveRow(false);
    return Plugin_Handled;
}

public Action Cmd_MatchRoster(int args) {
    if (args < 2) {
        LogMessage("[ClutchMatch] usage: clutch_match_roster <teamA_steam|steam> <teamB_steam|steam>");
        return Plugin_Handled;
    }

    g_hRoster.Clear();

    char teamA[512];
    char teamB[512];
    GetCmdArg(1, teamA, sizeof(teamA));
    GetCmdArg(2, teamB, sizeof(teamB));

    ParseRosterSide(teamA, 1);
    ParseRosterSide(teamB, 2);

    LogMessage("[ClutchMatch] roster loaded A+B");
    return Plugin_Handled;
}

void ParseRosterSide(const char[] pipeList, int slot) {
    char copy[512];
    strcopy(copy, sizeof(copy), pipeList);

    char parts[16][64];
    int count = ExplodeString(copy, "|", parts, sizeof(parts), sizeof(parts[]), false);
    for (int i = 0; i < count; i++) {
        TrimString(parts[i]);
        if (strlen(parts[i]) < 5) continue;
        char slotStr[4];
        IntToString(slot, slotStr, sizeof(slotStr));
        g_hRoster.SetString(parts[i], slotStr);
    }
}

public Action Cmd_MatchClear(int args) {
    LogMessage("[ClutchMatch] clear");
    ResetMatchState();
    if (g_hDb != null) {
        char sql[128];
        Format(sql, sizeof(sql), "DELETE FROM %s WHERE phase != 'idle'", TABLE_MATCH_LIVE);
        g_hDb.Query(SimpleQueryCallback, sql);
    }
    return Plugin_Handled;
}

public Action Cmd_MatchFinish(int args) {
    if (g_sMatchId[0] == '\0') {
        LogMessage("[ClutchMatch] no active match to finish");
        return Plugin_Handled;
    }
    FinalizeMatch();
    return Plugin_Handled;
}

public void SimpleQueryCallback(Database database, DBResultSet results, const char[] error, any data) {
    if (error[0]) {
        LogError("[ClutchMatch] query: %s", error);
    }
}

void ResetMatchState() {
    g_sMatchId[0] = '\0';
    strcopy(g_sPhase, sizeof(g_sPhase), "idle");
    g_iScoreA = 0;
    g_iScoreB = 0;
    g_iRound = 0;
    g_iMaxRounds = 30;
    g_iStartedAt = 0;
    g_iFinishedAt = 0;
    g_sWinner[0] = '\0';
    g_hRoster.Clear();
    g_hStats.Clear();
    if (g_aDeaths != null) g_aDeaths.Clear();
    if (g_aRounds != null) g_aRounds.Clear();
    if (g_aHighlights != null) g_aHighlights.Clear();
}

int GetActiveRoundNumber() {
    return g_iRound + 1;
}

void TeamSlotForSteam(const char[] steam, char[] buffer, int maxlen) {
    int slot = GetPlayerSlot(steam);
    if (slot == 1) {
        strcopy(buffer, maxlen, "A");
    } else if (slot == 2) {
        strcopy(buffer, maxlen, "B");
    } else {
        buffer[0] = '\0';
    }
}

void BumpRoundKill(const char[] steam, int roundNumber) {
    char key[96];
    Format(key, sizeof(key), "%s:rk:%d", steam, roundNumber);
    int value = 0;
    g_hStats.GetValue(key, value);
    g_hStats.SetValue(key, value + 1);
}

void AppendHighlight(const char[] steam, const char[] type, int roundNumber, const char[] detail) {
    char row[256];
    Format(
        row,
        sizeof(row),
        "{\"steamId\":\"%s\",\"type\":\"%s\",\"roundNumber\":%d,\"detail\":\"%s\"}",
        steam,
        type,
        roundNumber,
        detail
    );
    g_aHighlights.PushString(row);
}

void CheckRoundHighlights(int roundNumber) {
    StringMapSnapshot snap = g_hStats.Snapshot();
    for (int i = 0; i < snap.Length; i++) {
        char key[96];
        snap.GetKey(i, key, sizeof(key));

        char parts[3][64];
        if (ExplodeString(key, ":", parts, 3, sizeof(parts[]), false) != 3) {
            continue;
        }
        if (strcmp(parts[1], "rk") != 0) {
            continue;
        }
        if (StringToInt(parts[2]) != roundNumber) {
            continue;
        }

        int kills = 0;
        g_hStats.GetValue(key, kills);
        if (kills >= 5) {
            AppendHighlight(parts[0], "ACE", roundNumber, "Ace");
        } else if (kills >= 3) {
            char detail[32];
            Format(detail, sizeof(detail), "%d kills", kills);
            AppendHighlight(parts[0], "MULTI_KILL", roundNumber, detail);
        }
    }
    delete snap;
}

void AppendDeathRow(
    int roundNumber,
    const char[] victimSteam,
    const char[] killerSteam,
    const char[] weapon,
    bool headshot,
    const char[] victimTeam,
    float x,
    float y,
    float z
) {
    char row[320];
    Format(
        row,
        sizeof(row),
        "{\"roundNumber\":%d,\"victimSteamId\":\"%s\",\"killerSteamId\":\"%s\",\"weapon\":\"%s\",\"headshot\":%s,\"victimTeam\":\"%s\",\"x\":%.1f,\"y\":%.1f,\"z\":%.1f}",
        roundNumber,
        victimSteam,
        killerSteam,
        weapon,
        headshot ? "true" : "false",
        victimTeam,
        x,
        y,
        z
    );
    g_aDeaths.PushString(row);
}

void AppendRoundRow(int roundNumber, const char[] winnerTeam, int reason, bool bombPlanted) {
    char reasonText[32];
    if (reason == 1) {
        strcopy(reasonText, sizeof(reasonText), "target_bombed");
    } else if (reason == 7) {
        strcopy(reasonText, sizeof(reasonText), "bomb_defused");
    } else if (reason == 8) {
        strcopy(reasonText, sizeof(reasonText), "terrorists_win");
    } else if (reason == 9) {
        strcopy(reasonText, sizeof(reasonText), "ct_win");
    } else if (reason == 12) {
        strcopy(reasonText, sizeof(reasonText), "time_ran_out");
    } else {
        Format(reasonText, sizeof(reasonText), "reason_%d", reason);
    }

    char row[160];
    Format(
        row,
        sizeof(row),
        "{\"roundNumber\":%d,\"winnerTeam\":\"%s\",\"reason\":\"%s\",\"bombPlanted\":%s}",
        roundNumber,
        winnerTeam,
        reasonText,
        bombPlanted ? "true" : "false"
    );
    g_aRounds.PushString(row);
}

int GetPlayerSlot(const char[] steam) {
    char slotStr[8];
    if (!g_hRoster.GetString(steam, slotStr, sizeof(slotStr))) {
        return 0;
    }
    return StringToInt(slotStr);
}

void EnsurePlayerStat(const char[] steam) {
    if (g_hStats.ContainsKey(steam)) {
        return;
    }
    g_hStats.SetValue(steam, 1);
}

void BumpStat(const char[] steam, const char[] field, int delta) {
    char key[80];
    Format(key, sizeof(key), "%s:%s", steam, field);
    int value = 0;
    g_hStats.GetValue(key, value);
    g_hStats.SetValue(key, value + delta);
}

int GetStat(const char[] steam, const char[] field) {
    char key[80];
    Format(key, sizeof(key), "%s:%s", steam, field);
    int value = 0;
    g_hStats.GetValue(key, value);
    return value;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (g_sMatchId[0] == '\0' || StrEqual(g_sPhase, "idle")) return;
    if (!StrEqual(g_sPhase, "live")) return;

    int victimUserId = event.GetInt("userid");
    int attackerUserId = event.GetInt("attacker");
    int assisterUserId = event.GetInt("assister");

    int victim = GetClientOfUserId(victimUserId);
    if (victim <= 0 || !IsClientInGame(victim) || IsFakeClient(victim)) return;

    char victimSteam[32];
    if (!GetClientAuthId(victim, AuthId_Steam2, victimSteam, sizeof(victimSteam))) return;
    EnsurePlayerStat(victimSteam);
    BumpStat(victimSteam, "deaths", 1);

    bool headshot = event.GetBool("headshot");
    char weapon[48];
    event.GetString("weapon", weapon, sizeof(weapon));

    char killerSteam[32];
    killerSteam[0] = '\0';
    int attacker = GetClientOfUserId(attackerUserId);
    int roundNumber = GetActiveRoundNumber();

    if (attacker > 0 && attacker != victim && IsClientInGame(attacker) && !IsFakeClient(attacker)) {
        if (GetClientAuthId(attacker, AuthId_Steam2, killerSteam, sizeof(killerSteam))) {
            EnsurePlayerStat(killerSteam);
            BumpStat(killerSteam, "kills", 1);
            BumpRoundKill(killerSteam, roundNumber);
            if (headshot) {
                BumpStat(killerSteam, "headshots", 1);
            }
            if (StrContains(weapon, "awp", false) != -1) {
                BumpStat(killerSteam, "awp_kills", 1);
            }
        }
    }

    if (StrEqual(g_sPhase, "live")) {
        char victimTeam[2];
        TeamSlotForSteam(victimSteam, victimTeam, sizeof(victimTeam));
        float origin[3];
        GetClientAbsOrigin(victim, origin);
        AppendDeathRow(
            roundNumber,
            victimSteam,
            killerSteam,
            weapon,
            headshot,
            victimTeam,
            origin[0],
            origin[1],
            origin[2]
        );
    }

    int assister = GetClientOfUserId(assisterUserId);
    if (assister > 0 && assister != victim && assister != attacker && IsClientInGame(assister) && !IsFakeClient(assister)) {
        char assistSteam[32];
        if (GetClientAuthId(assister, AuthId_Steam2, assistSteam, sizeof(assistSteam))) {
            EnsurePlayerStat(assistSteam);
            BumpStat(assistSteam, "assists", 1);
        }
    }
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    if (g_sMatchId[0] == '\0' || StrEqual(g_sPhase, "idle")) return;

    int attackerUserId = event.GetInt("attacker");
    int victimUserId = event.GetInt("userid");
    if (attackerUserId == victimUserId) return;

    int attacker = GetClientOfUserId(attackerUserId);
    if (attacker <= 0 || !IsClientInGame(attacker) || IsFakeClient(attacker)) return;

    int victim = GetClientOfUserId(victimUserId);
    if (victim <= 0 || !IsClientInGame(victim)) return;

    // Ignore team damage so ADR reflects damage on enemies only.
    if (GetClientTeam(attacker) == GetClientTeam(victim)) return;

    int dmgHealth = event.GetInt("dmg_health");
    if (dmgHealth <= 0) return;

    char attackerSteam[32];
    if (!GetClientAuthId(attacker, AuthId_Steam2, attackerSteam, sizeof(attackerSteam))) return;
    EnsurePlayerStat(attackerSteam);
    BumpStat(attackerSteam, "damage", dmgHealth);
}

public void Event_RoundMvp(Event event, const char[] name, bool dontBroadcast) {
    if (g_sMatchId[0] == '\0') return;

    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) return;

    char steam[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam))) return;
    EnsurePlayerStat(steam);
    BumpStat(steam, "mvp", 1);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (g_sMatchId[0] == '\0') return;

    int winner = event.GetInt("winner");
    if (winner != CS_TEAM_CT && winner != CS_TEAM_T) return;

    int roundNumber = GetActiveRoundNumber();
    strcopy(g_sPhase, sizeof(g_sPhase), "live");

    int slot1OnWinner = 0;
    int slot2OnWinner = 0;

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        if (GetClientTeam(i) != winner) continue;

        char steam[32];
        if (!GetClientAuthId(i, AuthId_Steam2, steam, sizeof(steam))) continue;
        int slot = GetPlayerSlot(steam);
        if (slot == 1) slot1OnWinner++;
        else if (slot == 2) slot2OnWinner++;
    }

    char winnerTeam[2];
    if (slot1OnWinner >= slot2OnWinner) {
        g_iScoreA++;
        strcopy(winnerTeam, sizeof(winnerTeam), "A");
    } else {
        g_iScoreB++;
        strcopy(winnerTeam, sizeof(winnerTeam), "B");
    }

    int reason = event.GetInt("reason");
    bool bombPlanted = event.GetBool("bomb");
    CheckRoundHighlights(roundNumber);
    AppendRoundRow(roundNumber, winnerTeam, reason, bombPlanted);
    g_iRound++;

    int scoreCt = CS_GetTeamScore(CS_TEAM_CT);
    int scoreT = CS_GetTeamScore(CS_TEAM_T);

    if (g_hDb != null) {
        char sql[512];
        int now = GetTime();
        Format(
            sql,
            sizeof(sql),
            "REPLACE INTO %s (match_id,score_team_a,score_team_b,score_ct,score_t,round_num,phase,winner,max_rounds,started_at,finished_at,stats_json,updated_at) "
            ... "VALUES ('%s',%d,%d,%d,%d,%d,'live','',%d,%d,0,'',%d)",
            TABLE_MATCH_LIVE,
            g_sMatchId,
            g_iScoreA,
            g_iScoreB,
            scoreCt,
            scoreT,
            g_iRound,
            g_iMaxRounds,
            g_iStartedAt,
            now
        );
        g_hDb.Query(SimpleQueryCallback, sql);
    }
}

public void Event_MatchOver(Event event, const char[] name, bool dontBroadcast) {
    if (g_sMatchId[0] == '\0') return;
    FinalizeMatch();
}

void FinalizeMatch() {
    if (g_sPhase[0] == 'f') return;

    strcopy(g_sPhase, sizeof(g_sPhase), "finished");
    g_iFinishedAt = GetTime();

    if (g_iScoreA > g_iScoreB) {
        strcopy(g_sWinner, sizeof(g_sWinner), "A");
    } else if (g_iScoreB > g_iScoreA) {
        strcopy(g_sWinner, sizeof(g_sWinner), "B");
    } else {
        g_sWinner[0] = '\0';
    }

    // Capture score from connected players
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char steam[32];
        if (!GetClientAuthId(i, AuthId_Steam2, steam, sizeof(steam))) continue;
        EnsurePlayerStat(steam);
        int score = CS_GetClientContributionScore(i);
        char scoreKey[80];
        Format(scoreKey, sizeof(scoreKey), "%s:score", steam);
        g_hStats.SetValue(scoreKey, score);
    }

    PersistLiveRow(true);
    LogMessage("[ClutchMatch] finished %s A=%d B=%d winner=%s", g_sMatchId, g_iScoreA, g_iScoreB, g_sWinner);
}

void PersistLiveRow(bool final) {
    if (g_hDb == null || g_sMatchId[0] == '\0') return;

    char statsJson[16384];
    if (final) {
        BuildFinalPayloadJson(statsJson, sizeof(statsJson));
    } else {
        BuildStatsJson(statsJson, sizeof(statsJson));
    }

    char escapedStats[32768];
    g_hDb.Escape(statsJson, escapedStats, sizeof(escapedStats));

    int scoreCt = CS_GetTeamScore(CS_TEAM_CT);
    int scoreT = CS_GetTeamScore(CS_TEAM_T);
    int now = GetTime();
    int finishedAt = final ? g_iFinishedAt : 0;
    char phase[16];
    strcopy(phase, sizeof(phase), g_sPhase);

    char sql[12288];
    Format(
        sql,
        sizeof(sql),
        "REPLACE INTO %s (match_id,score_team_a,score_team_b,score_ct,score_t,round_num,phase,winner,max_rounds,started_at,finished_at,stats_json,updated_at) "
        ... "VALUES ('%s',%d,%d,%d,%d,%d,'%s','%s',%d,%d,%d,'%s',%d)",
        TABLE_MATCH_LIVE,
        g_sMatchId,
        g_iScoreA,
        g_iScoreB,
        scoreCt,
        scoreT,
        g_iRound,
        phase,
        g_sWinner,
        g_iMaxRounds,
        g_iStartedAt,
        finishedAt,
        escapedStats,
        now
    );
    g_hDb.Query(SimpleQueryCallback, sql);
}

void BuildStatsJson(char[] buffer, int maxlen) {
    buffer[0] = '[';
    int len = 1;
    bool first = true;

    StringMapSnapshot snap = g_hStats.Snapshot();
    for (int i = 0; i < snap.Length; i++) {
        char key[80];
        snap.GetKey(i, key, sizeof(key));

        // keys are steam:field or steam marker
        if (StrContains(key, ":") == -1) {
            continue;
        }

        char parts[2][64];
        if (ExplodeString(key, ":", parts, 2, sizeof(parts[]), false) != 2) continue;
        if (strcmp(parts[1], "kills") != 0) continue;

        char steam[64];
        strcopy(steam, sizeof(steam), parts[0]);

        if (!first) {
            len += Format(buffer[len], maxlen - len, ",");
        }
        first = false;

        int slot = GetPlayerSlot(steam);
        int kills = GetStat(steam, "kills");
        int deaths = GetStat(steam, "deaths");
        int assists = GetStat(steam, "assists");
        int mvp = GetStat(steam, "mvp");
        int score = GetStat(steam, "score");
        int headshots = GetStat(steam, "headshots");
        int damage = GetStat(steam, "damage");
        int awpKills = GetStat(steam, "awp_kills");

        len += Format(
            buffer[len],
            maxlen - len,
            "{\"steam\":\"%s\",\"slot\":%d,\"kills\":%d,\"deaths\":%d,\"assists\":%d,\"score\":%d,\"mvp\":%d,\"headshots\":%d,\"damage\":%d,\"awpKills\":%d}",
            steam,
            slot,
            kills,
            deaths,
            assists,
            score,
            mvp,
            headshots,
            damage,
            awpKills
        );

        if (len >= maxlen - 4) break;
    }

    delete snap;
    Format(buffer[len], maxlen - len, "]");
}

void JoinArrayListJson(ArrayList list, char[] buffer, int maxlen) {
    buffer[0] = '[';
    int len = 1;
    bool first = true;
    if (list != null) {
        for (int i = 0; i < list.Length; i++) {
            char row[512];
            list.GetString(i, row, sizeof(row));
            if (row[0] == '\0') continue;
            if (!first) {
                len += Format(buffer[len], maxlen - len, ",");
            }
            first = false;
            len += Format(buffer[len], maxlen - len, "%s", row);
            if (len >= maxlen - 8) break;
        }
    }
    Format(buffer[len], maxlen - len, "]");
}

void BuildFinalPayloadJson(char[] buffer, int maxlen) {
    char playersJson[4096];
    char roundsJson[2048];
    char deathsJson[8192];
    char highlightsJson[2048];

    BuildStatsJson(playersJson, sizeof(playersJson));
    JoinArrayListJson(g_aRounds, roundsJson, sizeof(roundsJson));
    JoinArrayListJson(g_aDeaths, deathsJson, sizeof(deathsJson));
    JoinArrayListJson(g_aHighlights, highlightsJson, sizeof(highlightsJson));

    Format(
        buffer,
        maxlen,
        "{\"players\":%s,\"rounds\":%s,\"deaths\":%s,\"highlights\":%s}",
        playersJson,
        roundsJson,
        deathsJson,
        highlightsJson
    );
}
