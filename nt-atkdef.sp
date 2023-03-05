#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

bool g_bActive;
bool g_bCapped;
int g_iJinraiSurvivorCount;
int g_iNsfSurvivorCount;
int g_abAlivePlayers[NEO_MAXPLAYERS];

public Plugin myinfo =
{
    name = "Neotokyo Attack/Defense Gamemode Plugin",
    author = "Hosomi",
    description = "Reward the defending team for timeouts",
    version = "0.1",
    url = ""
};

public void OnMapStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bActive = isAttackMap();
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bActive)
        return;
    if(g_bCapped) // Todo assign g_bCapped
        return;
    if(g_iJinraiSurvivorCount == 0 || g_iNsfSurvivorCount == 0)
        return;

    PrintToChatAll("Round timeout - correcting score...");

    // Check which side was attacking based on round number
    int round_num = GameRules_GetProp("m_iRoundNumber");
    round_num %= 2;
    int false_winner = TEAM_NONE;
    if(g_iJinraiSurvivorCount > g_iNsfSurvivorCount)
    {
        false_winner = TEAM_JINRAI;
    }
    if(g_iJinraiSurvivorCount < g_iNsfSurvivorCount)
    {
        false_winner = TEAM_NSF;
    }
    int true_winner = round_num ? TEAM_JINRAI : TEAM_NSF;
    PrintToChatAll("Actual round winner - Team %i", true_winner);
    if(false_winner == true_winner)
        return;
    
    // correct team scores
    int score;
    if(false_winner != TEAM_NONE)
    {
        score = GetTeamScore(false_winner);
        SetTeamScore(false_winner, score-1);
    }
    score = GetTeamScore(true_winner);
    SetTeamScore(true_winner, score+1);

    // correct player XP
    int xp;
    int team;
    for(int client = 1; client < NEO_MAXPLAYERS+1; ++client)
    {// this is liable to break if someone DCs and their slot gets filled during the post-round, but whatever ig
        if (!IsValidClient(client) || !IsClientInGame(client))
            continue;
        // Correct XP
        team = GetClientTeam(client);
        xp = GetPlayerXP(client);
        if(team == false_winner)
            SetPlayerXP(client, xp-1);
        else if (team == true_winner)
            SetPlayerXP(client, xp+1);
    }
}

// tracking the number of players alive at round end
public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bCapped = false;
    g_iJinraiSurvivorCount = 0;
    g_iNsfSurvivorCount = 0;
    for(int i = 0; i < NEO_MAXPLAYERS; ++i)
        g_abAlivePlayers[i] = false;
}
public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client == 0)
        return; // invalid client
    --client;
    if(GetClientTeam(client) != TEAM_JINRAI || GetClientTeam(client) != TEAM_NSF)
    {   // in case spectators count as "spawning"
        LogError("non-player client %i spawned", client);
        return;
    }
    g_abAlivePlayers[client] = true;    
    if(GetClientTeam(client) == TEAM_JINRAI)
        ++g_iJinraiSurvivorCount;
    else if(GetClientTeam(client) == TEAM_NSF)
        ++g_iNsfSurvivorCount;
}
public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client == 0)
    {
        LogError("Invalid client death");
        return; // invalid client
    }
    --client;
    PlayerDeath(client);
}
public void OnClientDisconnect(int client)
{
    if(g_abAlivePlayers[client])
        PlayerDeath(client);
}
//public void OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
//{
//    if(!event.GetBool("disconnect"))
//        return;
//    int client = GetClientOfUserId(event.GetInt("userid"));
//    if(client == 0)
//    {
//        LogError("Invalid client disconnect");
//        return; // invalid client
//    }
//    --client;
//    // ignore if player was already dead or speccing
//    if(g_abAlivePlayers[client] && IsValidClient(client))
//    {
//        switch(event.GetInt("oldteam"))
//        {
//            case TEAM_JINRAI: --g_iJinraiSurvivorCount;
//            case TEAM_NSF: --g_iNsfSurvivorCount;
//        }
//    }
//}
// Called from OnPlayerDeath and OnClientDisconnect
public void PlayerDeath(int client)
{
	// Did the death happen before round time ran out?
    int gamestate = GameRules_GetProp("m_iGameState");
    if (gamestate == 2 || gamestate == 1) // warmup or during round
    {
        g_abAlivePlayers[client] = false;   
        if(GetClientTeam(client) == TEAM_JINRAI)
            --g_iJinraiSurvivorCount;
        else if(GetClientTeam(client) == TEAM_NSF)
            --g_iNsfSurvivorCount;
    }
}

public void OnGhostCapture(int client)
{
    g_bCapped = true;
}


// CMDs
public Action CmdTest(int client, int args)
{
    if(g_bActive)
        ReplyToCommand(client, "Attack/Defend is running and active");
    else
        ReplyToCommand(client, "Attack/Defend is running but not active");
    return Plugin_Continue; 
}
public Action CmdQuery(int client, int args)
{
    ReplyToCommand(client, "Capped: %b\nJinrai survivors: %i\nNSF survivors: %i", g_bCapped, g_iJinraiSurvivorCount, g_iNsfSurvivorCount);
    return Plugin_Continue; 
}

// Non-callbacks
bool isAttackMap()
{
    // check 3rd token for atk suffix
    char currentMap[64];
    GetCurrentMap(currentMap, 64);
    char buffers[3][64];
    int splits = ExplodeString(currentMap, "_", buffers, sizeof(buffers), sizeof(buffers[]));
    if(splits < 3)
        return false;
    if (StrEqual(buffers[2], "atk"))
		return true;
	else
		return false;
}


public void OnPluginStart()
{
    RegConsoleCmd("sm_is_atk_running", CmdTest);
    RegConsoleCmd("sm_atk_query", CmdQuery);

    HookEvent("game_round_end",	    OnRoundEnd);
    HookEvent("game_round_start",	OnRoundStart);
    HookEvent("player_death",		OnPlayerDeath);
    HookEvent("player_spawn",		OnPlayerSpawn);
    //HookEvent("player_team",	    OnPlayerTeam);
}