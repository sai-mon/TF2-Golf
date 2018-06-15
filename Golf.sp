#include <sdktools>
#include <sourcemod>
#include <steamtools>

#define PLUGIN_VERSION "0.1a"
#pragma newdecls required

float Step;
float RadiusSize;
int pipeCounter[33];
int pipeDistanceCounter[33];
int pipeIndex[33];
float pipeLocation[33][3];

public Plugin myinfo =
{
	name = "TF2Golf",
	author = "duckbot",
	description = "Simple TF2 golf concept experiment",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/hidoikamo/"
}

public void OnPluginStart()
{
	CreateConVar("tf2golf", PLUGIN_VERSION, "Plugin Version", FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	char gameName[] = "TF2 Golf 0.1a";
	
	Steam_SetGameDescription(gameName);
		
	RadiusSize = 200 * 1.0;	
	Step = 20 * 1.0;
}

public void OnMapStart()
{
	CreateTimer(0.5, ScanStickyLocations, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void OnEntityCreated(int entity, const char[] classname) {
	if(StrEqual(classname, "tf_projectile_pipe", false)) {
		CreateTimer(0.1, Disarm_Pipe, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}
}


// For whatever reason I couldn't manage to load this plugin whenever I tried to use the native functions of stuck (https://forums.alliedmods.net/showthread.php?t=243151)
// Due to this I adapted the code needed to perform stuck detection & stuck fixing by using the code within said plugin
bool CheckIfPlayerIsStuck(int iClient)
{
	float vecMin[3];
	float vecMax[3];
	float vecOrigin[3];
	
	GetClientMins(iClient, vecMin);
	GetClientMaxs(iClient, vecMax);
	GetClientAbsOrigin(iClient, vecOrigin);
	
	TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_SOLID, TraceEntityFilterSolid);
	return TR_DidHit();
}

public bool TraceEntityFilterSolid(int entity, any contentsMask) 
{
	return entity > 1;
}

// Code for fixing a player's position when they get stuck after teleporting
bool FixPlayerPosition(int iClient)
{
	float pos_Z = 0.1;
	
	while(pos_Z <= RadiusSize && !TryFixPosition(iClient, 10.0, pos_Z))
	{	
		pos_Z = -pos_Z;
		if(pos_Z > 0.0)
			pos_Z += Step;
	}
	
	return !CheckIfPlayerIsStuck(iClient);
}

bool TryFixPosition(int iClient, float Radius, float pos_Z)
{
	float pixels = FLOAT_PI*2*Radius;
	float compteur;
	float vecPosition[3];
	float vecOrigin[3];
	float vecAngle[3];
	int coups = 0;
	
	GetClientAbsOrigin(iClient, vecOrigin);
	GetClientEyeAngles(iClient, vecAngle);
	vecPosition[2] = vecOrigin[2] + pos_Z;

	while(coups < pixels)
	{
		vecPosition[0] = vecOrigin[0] + Radius * Cosine(compteur * FLOAT_PI / 180);
		vecPosition[1] = vecOrigin[1] + Radius * Sine(compteur * FLOAT_PI / 180);

		TeleportEntity(iClient, vecPosition, vecAngle, NULL_VECTOR);
		if(!CheckIfPlayerIsStuck(iClient))
			return true;
		
		compteur += 360/pixels;
		coups++;
	}
	
	TeleportEntity(iClient, vecOrigin, vecAngle, NULL_VECTOR);
	if(Radius <= RadiusSize)
		return TryFixPosition(iClient, Radius + Step, pos_Z);
	
	return false;
}

public Action ScanStickyLocations(Handle timer)
{
	int iPipe = -1;
	
	// Scan for all available pipe
	while ((iPipe = FindEntityByClassname(iPipe, "tf_projectile_pipe")) != -1) //Called for every sticky bomb on the server
	{
		// Get the owner id of the current projectile
		int owner = GetEntPropEnt(iPipe, Prop_Send, "m_hThrower");
		
		PrintToChatAll("pipeIndex[owner] = %d iPipe = %d", pipeIndex[owner], iPipe);
		// Check if the owner has more than one projectile and if so remove it
		if(pipeIndex[owner] != iPipe && pipeCounter[owner] > 0) {
			PrintToChatAll("Too many stickies");
			AcceptEntityInput(iPipe, "Kill");
		}
		else {
			PrintToChatAll("Not too many stickies");
			// Check if the projectile is touching an area
			if (GetEntProp(iPipe, Prop_Send, "m_bTouched")) {
				
				// Get the location of the projectile
				float newPipeLocation[3];
				GetEntPropVector(iPipe, Prop_Send, "m_vecOrigin", newPipeLocation);				

				// Check if it's the first time this projectile is encountered, if so save location and nothing else
				if(pipeCounter[owner] == 0) {
					pipeIndex[owner] = iPipe;
					pipeDistanceCounter[owner] = 0;
					pipeCounter[owner] += 1;
					
					for (int i = 0; i < 3; i++) {
						pipeLocation[owner][i] = newPipeLocation[i];
					}
					
				}
				else {
					// Check if the projectile has moved less than a determined amount since the last check
					if((FloatAbs(pipeLocation[owner][0] - newPipeLocation[0]) < 30) && (FloatAbs(pipeLocation[owner][1] - newPipeLocation[1]) < 30) && (FloatAbs(pipeLocation[owner][2] - newPipeLocation[2]) < 30)) {
						
						if(pipeDistanceCounter[owner] < 3) {
							pipeDistanceCounter[owner] += 1;
						}
						else {
							pipeCounter[owner] -= 1;
							pipeIndex[owner] = -1;
							pipeDistanceCounter[owner] = 0;
							
							AcceptEntityInput(iPipe, "Kill"); 
							TeleportEntity(owner, newPipeLocation, NULL_VECTOR, NULL_VECTOR);
						}
						
						while (CheckIfPlayerIsStuck(owner))
						{
							char clientName[51];
							GetClientName(owner, clientName, 51);
							PrintToChatAll("LOL, %s IS STUCK", clientName);
							FixPlayerPosition(owner);
						}
					}
					else {
						for (int i = 0; i < 3; i++) {
							pipeLocation[owner][i] = newPipeLocation[i];
						}
					}
				}
			}	
		}
		break;
	}
	return Plugin_Continue;
}

public Action Disarm_Pipe(Handle timer, any ref) {
	// Create handle to pipe
	int pipe = EntRefToEntIndex(ref);
	
	// Check that pipe is valid
	if(pipe != INVALID_ENT_REFERENCE) {
		// Stop pipe from exploding
		SetEntProp(pipe, Prop_Data, "m_nNextThinkTick", -1);
	}
}

//public Action Check_If_Still(Handle timer, int pipe) {
//	static int counter[33];
//	
//	int owner = GetEntPropEnt(pipe, Prop_Send, "m_hThrower");
//	PrintToChatAll("Counter is: %d", counter[owner]);
//	
//	counter[owner] += 1;
//	
//	if(counter[owner] > 12) {
//		AcceptEntityInput(pipe, "Kill");
//		counter[owner] = 0;
//		CloseHandle(timer);
//		timer = INVALID_HANDLE;
//	}
//	return Plugin_Handled;
//	//float newpipeloc[3];
//	//GetEntPropVector(pipe, Prop_Send, "m_vecOrigin", newpipeloc);
//}