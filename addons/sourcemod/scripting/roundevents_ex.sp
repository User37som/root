/**
* RoundEvents Extended by Root
*
* Description:
*   Provides extended functionality for round events.
*
* Version 1.0
* Changelog & more info at http://goo.gl/4nKhJ
*/

#pragma semicolon 1

// ====[ SDKTOOLS ]=====================================================================
#include <sdktools_functions>

// ====[ CONSTANTS ]====================================================================
#define PLUGIN_NAME    "RoundEvents Extended"
#define PLUGIN_VERSION "1.0"

#define VOTE_YES       "###yes###"
#define VOTE_NO        "###no###"

#define BONUSROUNDMIN  1.0
#define BONUSROUNDMAX  60.0

// ====[ VARIABLES ]====================================================================
static const String:wallEnts[][] = { "func_team_wall", "func_teamblocker" };

enum
{
	DODTeam_Unassigned,
	DODTeam_Spectator,
	DODTeam_Allies,
	DODTeam_Axis
};

enum
{
	UnlockWall,
	BlockSpectators,
	ToggleAlltalk,
	SwitchTeamsAfter,
	SwitchTeamsImmunity,
	CallVoteForSwitch,

	ConVar_Size
};

enum ValueType
{
	ValueType_Bool,
	ValueType_Int,
	ValueType_Float
};

enum ConVar
{
	Handle:ConVarHandle,	// Handle of the convar
	ValueType:Type,			// Type of value (boolean, integer, float)
	any:Value				// The value
};

new	GetConVar[ConVar_Size][ConVar],
	Handle:SwitchVoteMenu,
	Handle:mp_allowspectators,
	Handle:sv_alltalk,
	Handle:dod_bonusroundtime,
	RoundsPlayed,
	bool:ShouldSwitch;

// ====[ PLUGIN ]=======================================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Provides extended functionality for round events",
	version     = PLUGIN_VERSION,
	url         = "http://www.dodsplugins.com/"
};


/* OnPluginStart()
 *
 * When the plugin starts up.
 * ------------------------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create console variables
	CreateConVar("dod_roundend_ex_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY);

	AddConVar(UnlockWall,          ValueType_Bool,  CreateConVar("dod_rex_unlockteamwall",      "1",    "Whether or not open opposite team wall after round end\nIt will be returned to the original state after round start", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(BlockSpectators,     ValueType_Bool,  CreateConVar("dod_rex_blockspectators",     "1",    "Whether or not disable avaliability to move to spectators after round end to prevent losers to avoid humiliation",    FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(ToggleAlltalk,       ValueType_Bool,  CreateConVar("dod_rex_togglealltalk",       "0",    "Whether or not disable restrictions for voice chat (sv_alltalk) on round end and turn it back when new round starts", FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(SwitchTeamsAfter,    ValueType_Int,   CreateConVar("dod_rex_switchafterrounds",   "4",    "Sets the amount ot rounds that required to call a vote/switch teams on next round\nSet to 0 to disable this feature", FCVAR_PLUGIN, true, 0.0));
	AddConVar(SwitchTeamsImmunity, ValueType_Bool,  CreateConVar("dod_rex_switchimmunity",      "0",    "Whether or not protect admins from being switched to another team on round start",                                    FCVAR_PLUGIN, true, 0.0, true, 1.0));
	AddConVar(CallVoteForSwitch,   ValueType_Float, CreateConVar("dod_rex_callvotebeforswitch", "0.60", "If value is specified (in percent), call a switch vote\nValue determines number of votes for successful voting",      FCVAR_PLUGIN, true, 0.0, true, 1.0));

	// Get default convars
	mp_allowspectators = FindConVar("mp_allowspectators");
	sv_alltalk         = FindConVar("sv_alltalk");
	dod_bonusroundtime = FindConVar("dod_bonusroundtime");

	// Hook needed events
	HookEvent("dod_round_win",   OnRoundEnd);
	HookEvent("dod_round_start", OnRoundStart, EventHookMode_Pre);
	HookEvent("player_team",     OnTeamChange, EventHookMode_Pre);

	// Create and exec plugin's config
	AutoExecConfig(true, "RoundEvents_Extended");

	// Why revient a wheel?
	LoadTranslations("basevotes.phrases");
	LoadTranslations("common.phrases");

	// Fuck the limits
	SetConVarBounds(dod_bonusroundtime, ConVarBound_Lower, true, BONUSROUNDMIN);
	SetConVarBounds(dod_bonusroundtime, ConVarBound_Upper, true, BONUSROUNDMAX);
}

/* OnConfigsExecuted()
 *
 * When the map has loaded and all plugin configs are done executing.
 * ------------------------------------------------------------------------------------- */
public OnConfigsExecuted()
{
	// Reset everything
	RoundsPlayed = false;
	ShouldSwitch = false;
}

/* OnConVarChange()
 *
 * Updates the stored convar value if the convar's value change.
 * ------------------------------------------------------------------------------------- */
public OnConVarChange(Handle:conVar, const String:oldValue[], const String:newValue[])
{
	for (new i = 0; i < ConVar_Size; i++)
	{
		if (conVar == GetConVar[i][ConVarHandle])
		{
			UpdateConVarValue(i);
		}
	}
}

/* OnRoundEnd()
 *
 * When a round ends.
 * ------------------------------------------------------------------------------------- */
public OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Add amount of total rounds played
	RoundsPlayed++;

	// If spectators should be blocked, disable it
	if (GetConVar[BlockSpectators][Value]) SetConVarBool(mp_allowspectators, false);

	// Lets suppress 'Value of sv_alltalk changed to 1' from chat area when round ends
	if (GetConVar[ToggleAlltalk][Value])
	{
		// Get original flags and remove which is showing changes in chat
		SetConVarFlags(sv_alltalk, GetConVarFlags(sv_alltalk) & ~FCVAR_NOTIFY);
		SetConVarBool(sv_alltalk,  true);
	}

	// Fuck restrictions?
	if (GetConVar[UnlockWall][Value])
	{
		// Let's search for entities
		new entity = -1;

		// Loop through and accept new collision group on wall entities of this map
		for (new i = 0; i < sizeof(wallEnts); i++)
		{
			while ((entity = FindEntityByClassname(entity, wallEnts[i])) != -1)
			{
				SetEntProp(entity, Prop_Send, "m_CollisionGroup", true);
			}
		}
	}

	// Make sure that we played enough amount of rounds
	if (GetConVar[SwitchTeamsAfter][Value] == RoundsPlayed)
	{
		// Call a vote if percent is defined
		if (GetConVar[CallVoteForSwitch][Value])
		{
			// Create vote handler
			SwitchVoteMenu = CreateMenu(SwitchTeamsVoteHandler, MenuAction:MENU_ACTIONS_ALL);

			SetMenuTitle(SwitchVoteMenu, "Switch teams after end of the round?");
			AddMenuItem(SwitchVoteMenu, VOTE_YES, "Yes");
			AddMenuItem(SwitchVoteMenu, VOTE_NO,  "No");

			// Dont allow client to close vote menu
			SetMenuExitButton(SwitchVoteMenu, false);

			// Show vote menu to all during bonusround time
			VoteMenuToAll(SwitchVoteMenu, GetConVarInt(dod_bonusroundtime) - 1);
		}

		// Reset amount of played rounds when teams should be switched
		RoundsPlayed = false;
		ShouldSwitch = true;
	}
}

/* OnRoundStart()
 *
 * Called when a round starts.
 * ------------------------------------------------------------------------------------- */
public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Enable spectators back
	if (GetConVar[BlockSpectators][Value]) SetConVarBool(mp_allowspectators, true);

	// Let's disable alltalk
	if (GetConVar[ToggleAlltalk][Value])
	{
		// Return notify flag
		SetConVarBool(sv_alltalk,  false);
		SetConVarFlags(sv_alltalk, GetConVarFlags(sv_alltalk) | FCVAR_NOTIFY);
	}

	// Make sure that previous teamwall state should be returned to an original one
	if (GetConVar[UnlockWall][Value])
	{
		new entity = -1;

		for (new i = 0; i < sizeof(wallEnts); i++)
		{
			// Since there may be more than 2 walls, lets loop again
			while ((entity = FindEntityByClassname(entity, wallEnts[i])) != -1)
			{
				// And set to original collision group though
				SetEntProp(entity, Prop_Send, "m_CollisionGroup", false);
			}
		}
	}

	// Are teams should be switched?
	if (ShouldSwitch == true)
	{
		// Switch function copied from <eVa> Dog code
		for (new client = 1; client <= MaxClients; client++)
		{
			// Make sure all players is in game
			if (IsClientInGame(client))
			{
				// Ignore admins from being switched if immunity is enabled
				if (GetConVar[SwitchTeamsImmunity][Value] && GetUserAdmin(client) != INVALID_ADMIN_ID) continue;

				if (GetClientTeam(client) == DODTeam_Allies) // is player on allies?
				{
					// Yep, get the other team
					ChangeClientTeam(client, DODTeam_Spectator);
					ChangeClientTeam(client, DODTeam_Axis);
					ShowVGUIPanel(client, "class_ger", INVALID_HANDLE, false);
				}
				else if (GetClientTeam(client) == DODTeam_Axis) // Nope.avi
				{
					// Needed to spectate players to switching teams without deaths (DoDS bug: you dont die when you join spectators)
					ChangeClientTeam(client, DODTeam_Spectator);
					ChangeClientTeam(client, DODTeam_Allies);
					ShowVGUIPanel(client, "class_us", INVALID_HANDLE, false);
				}
			}
		}

		// We no longer should be switched!
		ShouldSwitch = false;
	}
}

/* OnTeamChange()
 *
 * Called when a player changes team.
 * ------------------------------------------------------------------------------------- */
public OnTeamChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Lets suppress '*Player joined Wermacht/U.S' message
	if (ShouldSwitch) SetEventBroadcast(event, true);
}

/* SwitchTeamsVoteHandler()
 *
 * Called when a menu action is completed.
 * ------------------------------------------------------------------------------------- */
public SwitchTeamsVoteHandler(Handle:menu, MenuAction:action, client, param)
{
	// Get MenuHandler action
	switch (action)
	{
		case MenuAction_DisplayItem: // Item text is being drawn to the display
		{
			// Get menu item name and translate it
			decl String:display[8]; GetMenuItem(menu, param, "", 0, _, display, sizeof(display));
			if (StrEqual(display, "Yes") || StrEqual(display, "No"))
			{
				FormatEx(display, sizeof(display), "%T", display, client);
				return RedrawMenuItem(display);
			}
		}
		case MenuAction_End: // A menu display has fully ended
		{
			CloseHandle(SwitchVoteMenu);
			SwitchVoteMenu = INVALID_HANDLE;
		}
		case MenuAction_VoteCancel: // A vote sequence has been cancelled
		{
			if (client == VoteCancel_NoVotes) PrintToChatAll("\x04[TeamSwitch]\x05 %t", "No Votes Cast");
		}
		case MenuAction_VoteEnd: // A vote sequence has succeeded
		{
			decl String:item[8], String:display[8], Float:percent, Float:limit, votes, totalVotes;

			// Retrieve voting information
			GetMenuVoteInfo(param, votes, totalVotes);
			GetMenuItem(menu, client, item, sizeof(item), _, display, sizeof(display));

			if (StrEqual(item, VOTE_NO) && client == 1)
			{
				// Reverse the votes to be in relation to the Yes option.
				votes = totalVotes - votes;
			}

			// Get the percent
			percent = FloatDiv(float(votes), float(totalVotes));
			limit   = GetConVar[CallVoteForSwitch][Value];

			// Make sure that its a Yes/No vote
			if ((StrEqual(item, VOTE_YES) && FloatCompare(percent, limit) < 0 && client == 0)
			||  (StrEqual(item, VOTE_NO)  && client == 1))
			{
				PrintToChatAll("\x04[TeamSwitch]\x05 %t", "Vote Failed", RoundToNearest(100.0 * limit), RoundToNearest(100.0 * percent), totalVotes);
				ShouldSwitch = false;
			}
			else PrintToChatAll("\x04[TeamSwitch]\x05 %t", "Vote Successful", RoundToNearest(100.0 * percent), totalVotes);
		}
	}
	return false; // Because handler should return a value
}

/* AddConVar()
 *
 * Used to add a convar into the convar list.
 * ------------------------------------------------------------------------------------- */
AddConVar(conVar, ValueType:type, Handle:conVarHandle)
{
	GetConVar[conVar][ConVarHandle] = conVarHandle;
	GetConVar[conVar][Type] = type;

	UpdateConVarValue(conVar);

	HookConVarChange(conVarHandle, OnConVarChange);
}

/* UpdateConVarValue()
 *
 * Updates the internal convar values.
 * ------------------------------------------------------------------------------------- */
UpdateConVarValue(conVar)
{
	switch (GetConVar[conVar][Type])
	{
		case ValueType_Bool:  GetConVar[conVar][Value] = GetConVarBool (GetConVar[conVar][ConVarHandle]);
		case ValueType_Int:   GetConVar[conVar][Value] = GetConVarInt  (GetConVar[conVar][ConVarHandle]);
		case ValueType_Float: GetConVar[conVar][Value] = GetConVarFloat(GetConVar[conVar][ConVarHandle]);
	}
}