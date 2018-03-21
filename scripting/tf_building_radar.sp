/**
 * [TF2] Building Radar
 * 
 * Gives the Engineer building wallhacks.
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>

#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <clientprefs>
#define REQUIRE_PLUGIN

#pragma newdecls required
#include <stocksoup/tf/voice_hook>
#include <stocksoup/tf/entity_prefabs>

#define PLUGIN_VERSION "0.2.0"
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

bool g_bClientPrefsLoaded;
Handle g_BuildingRadarPreference;

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
	if (!PlayerHasBuildingRadarEnabled(client)) {
		return Plugin_Continue;
	}
	
	switch (command) {
		case Voice_TeleporterHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Teleporter)
					&& AttachTemporaryGlowsToBuiltEntities(client, "obj_teleporter")) {
				SetBuildingGlowCooldown(client, BuildingGlow_Teleporter);
				return Plugin_Stop;
			}
		}
		case Voice_DispenserHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Dispenser)
					&& AttachTemporaryGlowsToBuiltEntities(client, "obj_dispenser")) {
				SetBuildingGlowCooldown(client, BuildingGlow_Dispenser);
				return Plugin_Stop;
			}
		}
		case Voice_SentryHere: {
			if (!IsOnBuildingGlowCooldown(client, BuildingGlow_Sentry)
					&& AttachTemporaryGlowsToBuiltEntities(client, "obj_sentrygun")) {
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
	ClientCommand(client, "playgamesound %s", "CYOA.NodeActivate");
	g_BuildingGlowCooldowns[client][glow] = GetGameTime() + g_flGlowDuration;
}

void ResetBuildingGlowCooldown(int client, BuildingGlowRequests glow) {
	g_BuildingGlowCooldowns[client][glow] = 0.0;
}

bool AttachTemporaryGlowsToBuiltEntities(int owner, const char[] class) {
	int entity = -1;
	
	bool bAvailableBuildings = false;
	while ( (entity = FindEntityByClassname(entity, class)) != -1 ) {
		int hBuilder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
		if (hBuilder == owner) {
			int glow = TF2_AttachBasicGlow(entity);
			
			if (IsValidEntity(glow)) {
				SetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity", owner);
				SDKHook(glow, SDKHook_SetTransmit, OnBuildingGlow);
				
				bAvailableBuildings = true;
				
				char inputString[64];
				Format(inputString, sizeof(inputString), "%s %s:%s:%s:%.2f:%d", "OnUser1",
						"!self", "Kill", "", g_flGlowDuration, -1);
				
				SetVariantString(inputString);
				AcceptEntityInput(glow, "AddOutput");
				AcceptEntityInput(glow, "FireUser1");
			}
		}
	}
	return bAvailableBuildings;
}

public Action OnBuildingGlow(int glow, int client) {
	int hOwner = GetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity");
	
	if (hOwner == client) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

/* Client Preference settings */
public void ShowBuildingRadarPreferenceMenu(int client, CookieMenuAction action, any data,
		char[] buffer, int length) {
	if (action != CookieMenuAction_DisplayOption) {
		Menu forwardSpawnMenu = new Menu(OnBuildingRadarMenuHandled, MENU_ACTIONS_DEFAULT);
		
		forwardSpawnMenu.SetTitle("Enable Building Radar?");
		forwardSpawnMenu.AddItem("1", "Yes");
		forwardSpawnMenu.AddItem("0", "No");
		
		forwardSpawnMenu.ExitBackButton = true;
		forwardSpawnMenu.Display(client, 20);
	}
}

public int OnBuildingRadarMenuHandled(Menu menu, MenuAction action, int client, int selection) {
	switch (action) {
		case MenuAction_Select: {
			char info[4];
			menu.GetItem(selection, info, sizeof(info));
			
			bool bAllowForward = StringToInt(info) != 0;
			
			SetClientCookie(client, g_BuildingRadarPreference, info);
			OnBuildingRadarPreferenceUpdated(client, bAllowForward);
		}
		case MenuAction_Cancel: {
			if (selection == MenuCancel_ExitBack) {
				ShowCookieMenu(client);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
}

void OnBuildingRadarPreferenceUpdated(int client, bool bEnabled) {
	if (bEnabled) {
		PrintToChat(client, "You can now see your buildings through walls by using the "
				... "'* Here' voice menu options.");
	} else {
		PrintToChat(client, "Selecting the '* Here' voice menu options will only make the "
				... "player use those voice responses.");
	}
}

bool PlayerHasBuildingRadarEnabled(int client) {
	bool bDefaultSetting = false;
	if (g_bClientPrefsLoaded) {
		char buffer[4];
		GetClientCookie(client, g_BuildingRadarPreference, buffer, sizeof(buffer));
		
		if (strlen(buffer) == 0) {
			return bDefaultSetting;
		}
		return StringToInt(buffer) != 0;
	}
	return bDefaultSetting;
}

/* Client Preference library support */

void OnClientPrefsLoaded() {
	g_BuildingRadarPreference = RegClientCookie("tf_building_radar", "Allow players to see "
			... "their buildings through walls.", CookieAccess_Private);
	
	SetCookieMenuItem(ShowBuildingRadarPreferenceMenu, 0, "Building Radar");
}

#define CLIENTPREFS_LIBRARY "clientprefs"
public void OnAllPluginsLoaded() {
	g_bClientPrefsLoaded = LibraryExists(CLIENTPREFS_LIBRARY);
	
	if (g_bClientPrefsLoaded) {
		OnClientPrefsLoaded();
	}
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, CLIENTPREFS_LIBRARY)) {
		g_bClientPrefsLoaded = true;
		OnClientPrefsLoaded();
	}
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, CLIENTPREFS_LIBRARY)) {
		g_bClientPrefsLoaded = false;
	}
}
