#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

Handle g_cvIsolation;
//Handle g_cvInverted;
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
    version = "1.3",
    url = ""
};

public void OnMapStart()
{
    g_bActive = isAttackMap();
    if(g_bActive)
        LogMessage("Attack/Defend mode activated");
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bActive)
        return;
    if(g_bCapped)
        return;
    if(g_iJinraiSurvivorCount == 0 || g_iNsfSurvivorCount == 0)
        return;

    PrintToChatAll("Round timeout - awarding round win and xp to defending team");

    // Check which side was attacking based on round number
    int eAttackers = GameRules_GetProp("m_iAttackingTeam");
    // If an admin has told us that things are the wrong way around, swap them
//    if(g_cvInverted)
//    {
//        eAttackers = eAttackers == TEAM_NSF ? TEAM_JINRAI : TEAM_NSF;
//    }

    int eFalseWinner = TEAM_NONE;
    if(g_iJinraiSurvivorCount > g_iNsfSurvivorCount)
    {
        eFalseWinner = TEAM_JINRAI;
    }
    if(g_iJinraiSurvivorCount < g_iNsfSurvivorCount)
    {
        eFalseWinner = TEAM_NSF;
    }
    int eTrueWinner = eAttackers == TEAM_NSF ? TEAM_JINRAI : TEAM_NSF;
    if(eFalseWinner == eTrueWinner)
        return;
    
    // correct team scores
    int score;
    if(eFalseWinner != TEAM_NONE)
    {
        score = GetTeamScore(eFalseWinner);
        SetTeamScore(eFalseWinner, score-1);
    }
    score = GetTeamScore(eTrueWinner);
    SetTeamScore(eTrueWinner, score+1);

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
        if(team == eFalseWinner)
            SetPlayerXP(client, xp-1);
        else if (team == eTrueWinner)
            SetPlayerXP(client, xp+1);
    }
}

// tracking the number of players alive at round end
public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bActive)
        return;
    
    g_bCapped = false;
    g_iJinraiSurvivorCount = 0;
    g_iNsfSurvivorCount = 0;
    for(int i = 0; i < NEO_MAXPLAYERS; ++i)
        g_abAlivePlayers[i] = false;

    // Communicate to PUB noobs how the game works
    PrintToChatAll("[Attack/Defend] - Defending team wins if time runs out!");
    if(GameRules_GetProp("m_iAttackingTeam") == TEAM_NSF)
        PrintToChatAll("[Attack/Defend] - Jinrai is defending");
    else
        PrintToChatAll("[Attack/Defend] - NSF is defending");
}
public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bActive)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client == 0)
        return; // invalid client
    if(GetClientTeam(client) != TEAM_JINRAI && GetClientTeam(client) != TEAM_NSF)
    {   // in case spectators count as "spawning"
        return;
    }
    g_abAlivePlayers[client-1] = true;
    if(GetClientTeam(client) == TEAM_JINRAI)
        ++g_iJinraiSurvivorCount;
    else if(GetClientTeam(client) == TEAM_NSF)
        ++g_iNsfSurvivorCount;
}
public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if(!g_bActive)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client == 0)
    {
        LogError("Invalid client death");
        return; // invalid client
    }
    PlayerDeath(client);
}
public void OnClientDisconnect(int client)
{
    if(!g_bActive)
        return;

    if(g_abAlivePlayers[client-1])
        PlayerDeath(client);
}

// Called from OnPlayerDeath and OnClientDisconnect
public void PlayerDeath(int client)
{
	// Did the death happen before round time ran out?
    int gamestate = GameRules_GetProp("m_iGameState");
    if (gamestate == 2 || gamestate == 1) // warmup or during round
    {
        int team = GetClientTeam(client);
        g_abAlivePlayers[client-1] = false;
        if(team == TEAM_JINRAI)
            --g_iJinraiSurvivorCount;
        else if(team == TEAM_NSF)
            --g_iNsfSurvivorCount;
    }
}

public void OnGhostCapture(int client)
{
    g_bCapped = true;
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
    if(g_cvIsolation && StrEqual(buffers[1],"isolation"))
        return true;
    return false;
}

public void OnPluginStart()
{
    g_cvIsolation = CreateConVar("sm_atk_on_isolation", "1", "enables the attack/defense gamemode on nt_isolation_ctg");
//    g_cvInverted =  CreateConVar("sm_atk_switch", "0", "If the side tracker has desynced with the team spawns, toggle this cvar");
//    RegAdminCmd("sm_atk_switchSides", CmdSwitch, ADMFLAG_GENERIC, "switch the expected sides, used to fix tracking");
//    RegConsoleCmd("sm_atk_isSwitched", CmdIsInverted, "Says whether the spawn tracking is currently switched");
    RegConsoleCmd("sm_atk_isActive",   CmdIsActive, "Says whether the atk/def plugin is currently active");
    RegConsoleCmd("sm_atk_whoDef",     CmdWhoDef, "Says whether the atk/def plugin is currently active");

    HookEvent("game_round_end",     OnRoundEnd);
    HookEvent("game_round_start",   OnRoundStart);
    HookEvent("player_death",       OnPlayerDeath);
    HookEvent("player_spawn",       OnPlayerSpawn);
}

//public Action CmdSwitch(int client, int args)
//{
//    if(g_cvInverted)
//    {
//        g_cvInverted = 0;
//    }
//    else
//    {
//        g_cvInverted = 1;
//    }    
//
//    
//    int eAttackers = GameRules_GetProp("m_iAttackingTeam");
//    if(g_cvInverted)
//    {
//        eAttackers = eAttackers == TEAM_NSF ? TEAM_JINRAI : TEAM_NSF;
//    }
//    if(eAttackers == TEAM_JINRAI)
//    {
//        ReplyToCommand(client, "[ATK/DEF] Switched sides. Jinrai is currently defending");
//    }
//    else if(eAttackers == TEAM_NSF)
//    {
//        ReplyToCommand(client, "[ATK/DEF] Switched sides. NSF is currently defending");
//    }
//
//    return Plugin_Handled;
//}

// All these if elses are nasty but idc
//public Action CmdIsInverted(int client, int args)
//{
//    if(g_cvInverted)
//    {
//        ReplyToCommand(client, "[ATK/DEF] currently switched");
//    }
//    else
//    {
//        ReplyToCommand(client, "[ATK/DEF] not switched");
//    }
//    return Plugin_Handled;
//}

public Action CmdIsActive(int client, int args)
{
    if(g_bActive)
    {
        ReplyToCommand(client, "[ATK/DEF] currently active");
    }
    else
    {
        ReplyToCommand(client, "[ATK/DEF] not active");
    }
    return Plugin_Handled;
}

public Action CmdWhoDef(int client, int args)
{
    int eAttackers = GameRules_GetProp("m_iAttackingTeam");
//    if(g_cvInverted)
//    {
//        eAttackers = eAttackers == TEAM_NSF ? TEAM_JINRAI : TEAM_NSF;
//    }
    if(eAttackers == TEAM_JINRAI)
    {
        ReplyToCommand(client, "[ATK/DEF] NSF is defending");
    }
    else if (eAttackers == TEAM_NSF)
    {
        ReplyToCommand(client, "[ATK/DEF] Jinrai is defending");
    }
    else
    {
        ReplyToCommand(client, "[ATK/DEF] Unknown team is defending... wtf");
    }
    return Plugin_Handled;
}