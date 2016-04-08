/**
 * [TF2] Building Radar
 * 
 * Gives the Engineer building wallhacks.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <stocksoup/tf/voice_hook>
#include <stocksoup/tf/glow_model>

#define PLUGIN_VERSION "0.0.1"
public Plugin myinfo = {
    name = "[TF2] Building Radar",
    author = "nosoop",
    description = "Allows the Engineer to see his buildings through walls on voice command.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFBuildingRadar"
}

enum BuildingGlowRequests {
	BuildingGlow_Teleporter,
	BuildingGlow_Dispenser,
	BuildingGlow_Sentry
};

float g_BuildingGlowCooldowns[MAXPLAYERS+1][BuildingGlowRequests];

float g_flGlowDuration = 10.0;

public void OnPluginStart() {
	RegisterVoiceMenuListener();
	
	RegisterVoiceCommandCallback(Voice_TeleporterHere, OnBuildingVoiceCommand);
	RegisterVoiceCommandCallback(Voice_DispenserHere, OnBuildingVoiceCommand);
	RegisterVoiceCommandCallback(Voice_SentryHere, OnBuildingVoiceCommand);
}

public void OnClientDisconnect(int client) {
	for (int i = 0; i < view_as<int>(BuildingGlowRequests); i++) {
		ResetBuildingGlowCooldown(client, view_as<BuildingGlowRequests>(i));
	}
}

public Action OnBuildingVoiceCommand(int client, TFVoiceCommand command) {
	switch (command) {
		case Voice_TeleporterHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Teleporter)) {
				AttachTemporaryGlowsToBuiltEntities(client, "obj_teleporter");
				SetBuildingGlowCooldown(client, BuildingGlow_Teleporter);
				return Plugin_Stop;
			}
		}
		case Voice_DispenserHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Dispenser)) {
				AttachTemporaryGlowsToBuiltEntities(client, "obj_dispenser");
				SetBuildingGlowCooldown(client, BuildingGlow_Dispenser);
				return Plugin_Stop;
			}
		}
		case Voice_SentryHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Sentry)) {
				AttachTemporaryGlowsToBuiltEntities(client, "obj_sentrygun");
				SetBuildingGlowCooldown(client, BuildingGlow_Sentry);
				return Plugin_Stop;
			}
		}
	}
	return Plugin_Continue;
}

bool IsOnBuildingGlowCooldown(int client, BuildingGlowRequests glow) {
	return g_BuildingGlowCooldowns[client][glow] > GetGameTime();
}

void SetBuildingGlowCooldown(int client, BuildingGlowRequests glow) {
	g_BuildingGlowCooldowns[client][glow] = GetGameTime() + g_flGlowDuration;
}

void ResetBuildingGlowCooldown(int client, BuildingGlowRequests glow) {
	g_BuildingGlowCooldowns[client][glow] = 0.0;
}

void AttachTemporaryGlowsToBuiltEntities(int owner, const char[] class) {
	int entity = -1;
	
	while ( (entity = FindEntityByClassname(entity, class)) != -1 ) {
		int hBuilder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
		if (hBuilder == owner) {
			int glow = AddGlowModel(entity, view_as<TFTeam>(GetClientTeam(owner)));
			
			if (IsValidEntity(glow)) {
				SetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity", owner);
				SDKHook(glow, SDKHook_SetTransmit, OnBuildingGlow);
				
				CreateTimer(g_flGlowDuration, OnBuildingGlowExpired, EntIndexToEntRef(glow));
			}
		}
	}
}

public Action OnBuildingGlowExpired(Handle timer, int glowref) {
	int glow = EntRefToEntIndex(glowref);
	
	if (IsValidEntity(glow) && glow != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(glow, "Kill");
	}
}

public Action OnBuildingGlow(int glow, int client) {
	int hOwner = GetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity");
	
	if (hOwner == client) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}
