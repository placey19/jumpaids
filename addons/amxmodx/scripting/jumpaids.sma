#pragma semicolon 1;

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include "beams.inc"

#define PLUGIN		"JumpAids"
#define VERSION		"1.21"
#define AUTHOR		"Necro"

#define OWNER_INT	EV_INT_iuser4		//entity int id to hold the owner of the jumpaids
#define FREEZE_BUTTONS	IN_USE			//buttons to be pressed by the player to freeze the aids

//constants
new const gszPrefix[] = "!w[!tJUMPAIDS!w] !g";
new const gszInfoTarget[] = "info_target";
new const gszJumpAidsPrefix[] = "jumpaids";
new const gszJumpAidsMainMenu[] = "jumpaids_mainmenu";
new const gszDigitClassname[] = "jumpaids_digit";
new const gszDistanceClassname[] = "jumpaids_distance";
new const gszJumpEdgeClassname[] = "jumpaids_jumpedge";
new const gszDotSprite[] = "sprites/jumpaids/dot.spr";
new const gszSmoothDotSprite[] = "sprites/dot.spr";
new const gszDigits[] = "sprites/jumpaids/digits.spr";
new const gszCvarDefaultOn[] = "jumpaids_defaulton";
new const gszStatusIconSpriteName[] = "dmg_shock";	//d_headshot
new const Float:gfDigitOffsetMultipliers[3] = { 0.8, 0.0, 0.8 };
new const Float:gfColorLj[3] = { 0.0, 255.0, 0.0 };
new const Float:gfColorHj[3] = { 200.0, 80.0, 0.0 };
new const Float:gfForwardDist = 125.0;		//how far forward the initial trace will start from
new const Float:gfMinLjLength = 100.0;		//minimum length of LJ allowed for distance to be shown
new const Float:gfMaxLjLength = 300.0;		//maximum allowed LJ length
new const Float:gfDistanceBeamWidth = 2.0;	//width of the distance beam
new const Float:gfJumpEdgeBeamWidth = 1.0;	//width of the jump edge beam
new const Float:gfJumpEdgeBeamLength = 60.0;	//length of the jump edge beam
new const Float:gfHeadBangTraceHeight = 45.0;	//height above players head to trace for headbangers
new const Float:gfFreezeDuration = 3.0;		//duration that the distance and jumps aids remain frozen

//enum for menu option values
enum
{
	N1, N2, N3, N4, N5, N6, N7, N8, N9, N0
};

//enum for bit-shifted numbers 1 - 10 for main menu
enum
{
	B1 = 1 << N1, B2 = 1 << N2, B3 = 1 << N3, B4 = 1 << N4, B5 = 1 << N5,
	B6 = 1 << N6, B7 = 1 << N7, B8 = 1 << N8, B9 = 1 << N9, B0 = 1 << N0,
};

//global variables
new gMaxPlayers;
new gMsgSayText;
new gMsgStatusIcon;
new gDistanceEnt[33];
new gDistanceValueEnts[33][3];
new gJumpEdgeEnt[33];
new gKeysMainMenu;
new gszMainMenu[256];
new bool:gbDistanceOn[33];
new bool:gbJumpEdgeOn[33];
new bool:gbHeadBangOn[33];
new bool:gbMainMenuOpen[33];
new Float:gfHeadBangHudIconColor[33][3];
new Float:gfGroundTime[33];
new Float:gfFreezeTime[33];

public plugin_precache() {
	precache_model(gszDotSprite);
	precache_model(gszSmoothDotSprite);
	precache_model(gszDigits);
}

public plugin_init() {
	//register plugin and server variable so servers running this plugin can be searched for
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_cvar(PLUGIN, VERSION, FCVAR_SERVER, 0.0);
	
	//register forwards
	register_forward(FM_AddToFullPack, "addToFullPack", 1);
	
	//register client commands
	register_clcmd("togglejumpaids", "toggleAllJumpAids");
	register_clcmd("jumpaids", "showMainMenu");
	register_clcmd("say /jumpaids", "showMainMenu");
	register_clcmd("say /ja", "showMainMenu");
	
	//register CVARs
	register_cvar(gszCvarDefaultOn, "1");	//default condition - all players start with aids! :D
	
	//create main menu
	new size = sizeof(gszMainMenu);
	add(gszMainMenu, size, "\yJumpAids Menu^n^n");
	add(gszMainMenu, size, "\r1. \wDistance: %s^n");
	add(gszMainMenu, size, "\r2. \wEdge: %s^n");
	add(gszMainMenu, size, "\r3. \wHeadbang: %s^n^n");
	add(gszMainMenu, size, "\r0. \wClose");
	gKeysMainMenu = (B1 | B2 | B3 | B0);
	register_menucmd(register_menuid(gszJumpAidsMainMenu), gKeysMainMenu, "handleMainMenu");
}

public plugin_cfg() {
	//set maximum number of players
	gMaxPlayers = get_maxplayers();
	
	//get message ids
	gMsgSayText = get_user_msgid("SayText");
	gMsgStatusIcon = get_user_msgid("StatusIcon");
}

public client_PostThink(id) {
	handleJumpAids(id);
}

public addToFullPack(ent_state, e, ent, host, hostflags, player, pSet) {
	if (!player && is_user_connected(host) && isJumpAidsEntity(ent)) {
		new entOwner = entity_get_int(ent, OWNER_INT);
		
		//only show players own jumpaids or the aids of those they are spectating
		if (host == entOwner || isSpectating(host, entOwner)) {
			set_es(ent_state, ES_RenderAmt, entity_get_float(ent, EV_FL_renderamt));
		} else {
			set_es(ent_state, ES_RenderAmt, 0.0);
		}
	}
	
	return 1;
}

public client_connect(id) {
	if (get_cvar_num(gszCvarDefaultOn) > 0) {
		gbDistanceOn[id] = true;
		gbJumpEdgeOn[id] = true;
		gbHeadBangOn[id] = true;
	}
	gbMainMenuOpen[id] = false;
}

public client_spawn(id) {
	hideHeadBangHudIcon(id);
}

public client_disconnected(id) {
	hideDistance(id);
	hideJumpEdge(id);
	gbDistanceOn[id] = false;
	gbJumpEdgeOn[id] = false;
	gbHeadBangOn[id] = false;
	gbMainMenuOpen[id] = false;
}

public toggleAllJumpAids(const id) {
	//toggle all jump aids depending on the state of the distance aid
	if (!gbDistanceOn[id]) {
		gbDistanceOn[id] = true;
		gbJumpEdgeOn[id] = true;
		gbHeadBangOn[id] = true;
		client_printc(id, print_chat, "%sAll jump aids enabled.", gszPrefix);
	} else {
		gbDistanceOn[id] = false;
		gbJumpEdgeOn[id] = false;
		gbHeadBangOn[id] = false;
		client_printc(id, print_chat, "%sAll jump aids disabled.", gszPrefix);
	}
	
	//refresh main menu if it's open
	if (gbMainMenuOpen[id]) {
		showMainMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

public showMainMenu(const id) {
	//format the main menu
	static szMenu[256];
	static szDistanceState[6];
	static szJumpEdgeState[6];
	static szHeadBangState[6];
	szDistanceState = (gbDistanceOn[id] ? "\yOn" : "\rOff");
	szJumpEdgeState = (gbJumpEdgeOn[id] ? "\yOn" : "\rOff");
	szHeadBangState = (gbHeadBangOn[id] ? "\yOn" : "\rOff");
	format(szMenu, 256, gszMainMenu, szDistanceState, szJumpEdgeState, szHeadBangState);
	
	//show the main menu to the player
	show_menu(id, gKeysMainMenu, szMenu, -1, gszJumpAidsMainMenu);
	gbMainMenuOpen[id] = true;
	
	return PLUGIN_HANDLED;
}

public handleMainMenu(const id, const num) {
	switch (num) {
		case N1: {
			gbDistanceOn[id] = !gbDistanceOn[id];
			client_printc(id, print_chat, "%sDistance jump aid %sabled.", gszPrefix, (gbDistanceOn[id] ? "en" : "dis"));
		}
		case N2: {
			gbJumpEdgeOn[id] = !gbJumpEdgeOn[id];
			client_printc(id, print_chat, "%sEdge jump aid %sabled.", gszPrefix, (gbJumpEdgeOn[id] ? "en" : "dis"));
		}
		case N3: {
			gbHeadBangOn[id] = !gbHeadBangOn[id];
			client_printc(id, print_chat, "%sHeadbang jump aid %sabled.", gszPrefix, (gbHeadBangOn[id] ? "en" : "dis"));
		}
		case N0: {
			gbMainMenuOpen[id] = false;
			return;
		}
	}
	
	//display menu again
	showMainMenu(id);
	gbMainMenuOpen[id] = true;
}

/**
 * Test if given entity is a valid JumpAids entity.
 */
bool:isJumpAidsEntity(const ent) {
	if (is_valid_ent(ent)) {
		static szClassname[32];
		entity_get_string(ent, EV_SZ_classname, szClassname, 32);
		if (strfind(szClassname, gszJumpAidsPrefix) != -1) {
			return true;
		}
	}
	
	return false;
}

/**
 * Test if the given player is spectating the target player.
 */
bool:isSpectating(const id, const targetId) {
	new specId = entity_get_int(id, EV_INT_iuser2);
	return (targetId == specId);
}

/**
 * Do various traces to get and show the jump information.
 */
handleJumpAids(const id) {
	static bool:bDistanceVisible;
	static bool:bJumpEdgeVisible;
	static bool:bHeadBangVisible;
	static bool:bJumpAidEnabled;
	static bool:isOnGround;
	static Float:timeOffGround;
	static flags;
	
	bDistanceVisible = (gfFreezeTime[id] > 0.0);
	bJumpEdgeVisible = (gfFreezeTime[id] > 0.0);
	bHeadBangVisible = false;
	bJumpAidEnabled = (gbDistanceOn[id] || gbJumpEdgeOn[id] || gbHeadBangOn[id]);
	
	//get whether or not the player is on the ground
	flags = entity_get_int(id, EV_INT_flags);
	isOnGround = (flags & FL_ONGROUND > 0 ? true : false);
	
	timeOffGround = 0.0;
	if (is_user_alive(id)) {
		//get the amount of time the player has been off the ground (in the air or water)
		if (!isOnGround) {
			if (gfGroundTime[id] == 0.0) {
				gfGroundTime[id] = halflife_time();
			} else {
				timeOffGround = (halflife_time() - gfGroundTime[id]);
			}
		} else if (gfGroundTime[id] != 0.0) {
			gfGroundTime[id] = 0.0;
		}
		
		if (isOnGround && bJumpAidEnabled) {
			static Float:vTraceEndPos[3];
			static Float:vPlayerOrigin[3];
			static Float:vPlayerDirection[3];
			static Float:fPlayerAbsMin[3];
			static Float:fPlayerAbsMax[3];
			static Float:fPlayerAngles[3];
			static Float:fHeightDelta;
			
			//get player vectors of interest
			entity_get_vector(id, EV_VEC_origin, vPlayerOrigin);
			entity_get_vector(id, EV_VEC_absmin, fPlayerAbsMin);
			entity_get_vector(id, EV_VEC_absmax, fPlayerAbsMax);
			entity_get_vector(id, EV_VEC_angles, fPlayerAngles);
			fPlayerAbsMin[2] += 0.9;	//needs doing, dunno why...
			
			//if the distance and edge aids aren't frozen
			if (gfFreezeTime[id] == 0.0) {
				//calculate unit vector for the direction the player is facing - the yaw only
				xs_vec_set(vPlayerDirection, floatcos(fPlayerAngles[1], degrees), floatsin(fPlayerAngles[1], degrees), 0.0);
			
				//trace down in front of player, don't care if it hits anything or not
				traceDownInFrontOfPlayer(id, vPlayerOrigin, vPlayerDirection, fPlayerAbsMin, fPlayerAbsMax, vTraceEndPos);
				
				//get height difference between trace end point and players feet
				fHeightDelta = (fPlayerAbsMin[2] - vTraceEndPos[2]);
				if (fHeightDelta > 8.0) {
					static Float:vJumpEdge[3];
					static Float:vNormal[3];
					static bool:bHit;
					
					bHit = traceBackwardsTowardsPlayer(id, vTraceEndPos, vPlayerDirection, fPlayerAbsMin, vJumpEdge, vNormal);
					if (bHit) {
						static Float:fHeight;
						static bool:bIsHj;
						fHeight = traceDownForDropHeight(id, vJumpEdge);
						bIsHj = (fHeight > 69.5);
						
						if (gbJumpEdgeOn[id]) {
							showJumpEdge(id, vJumpEdge, vNormal, bIsHj, gfJumpEdgeBeamLength);
							bJumpEdgeVisible = true;
						}
						
						if (gbDistanceOn[id]) {
							bHit = traceForwardsForDistance(id, vJumpEdge, vNormal, gfMaxLjLength, vTraceEndPos);
							if (bHit) {
								static Float:fDistance;
								static distance;
								fDistance = get_distance_f(vJumpEdge, vTraceEndPos);
								distance = floatround(fDistance, floatround_round);
								
								if (fDistance >= gfMinLjLength) {
									showDistance(id, vJumpEdge, vTraceEndPos, vNormal, distance, (bIsHj ? gfColorHj : gfColorLj));
									bDistanceVisible = true;
								}
							}
						}
					}
				}
			}
			
			if (gbHeadBangOn[id]) {
				static Float:vPlayerViewOffset[3];
				entity_get_vector(id, EV_VEC_view_ofs, vPlayerViewOffset);
				
				new Float:fDistance = traceAbovePlayerHead(id, vPlayerOrigin, vPlayerViewOffset);
				if (fDistance > 0.0) {
					static Float:fColor[3];
					xs_vec_set(fColor, 255.0, map(fDistance, 0.0, gfHeadBangTraceHeight, 0.0, 255.0), 0.0);
					showHeadBangHudIcon(id, fColor);
					bHeadBangVisible = true;
				}
			}
		}
	}
	
	//handle headbang aid for spectators
	if (!is_user_alive(id)) {
		new specId = entity_get_int(id, EV_INT_iuser2);
		if (specId != 0) {
			showHeadBangHudIcon(id, gfHeadBangHudIconColor[specId]);
			bHeadBangVisible = true;
		}
	}
	
	//freeze the distance and edge aids when the player presses the use button
	if (bDistanceVisible || bJumpEdgeVisible) {
		if (gfFreezeTime[id] == 0.0) {
			if (entity_get_int(id, EV_INT_button) & FREEZE_BUTTONS == FREEZE_BUTTONS) {
				gfFreezeTime[id] = halflife_time();
			}
		} else if ((halflife_time() - gfFreezeTime[id]) > gfFreezeDuration) {
			gfFreezeTime[id] = 0.0;
		}
	}
	
	//hide the distance aid if it's not supposed to be visible and isn't frozen
	if (!bDistanceVisible && gfFreezeTime[id] == 0.0) {
		hideDistance(id);
	}
	
	//hide the jump-edge aid if it's not supposed to be visible and isn't frozen
	if (!bJumpEdgeVisible && gfFreezeTime[id] == 0.0) {
		hideJumpEdge(id);
	}
	
	//hide the headbang aid if it's not supposed to be visible
	if (!bHeadBangVisible && (!is_user_alive(id) || isOnGround || timeOffGround > 0.75)) {
		hideHeadBangHudIcon(id);
	}
}

/**
 * Show the headbang hud icon to the given player. Messages won't be sent to the client unless the
 * data has changed so repetitive calls to this method is ok.
 */
showHeadBangHudIcon(const id, const Float:fColor[3]) {
	if (!xs_vec_equal(gfHeadBangHudIconColor[id], fColor)) {
		message_begin(MSG_ONE, gMsgStatusIcon, { 0, 0, 0 }, id);
		write_byte(1);
		write_string(gszStatusIconSpriteName);
		write_byte(floatround(fColor[0], floatround_round));
		write_byte(floatround(fColor[1], floatround_round));
		write_byte(floatround(fColor[2], floatround_round));
		message_end();
		
		xs_vec_set(gfHeadBangHudIconColor[id], fColor[0], fColor[1], fColor[2]);
	}
}

/**
 * Hide the hud headbanger icon for the given player. Messages won't be sent to the client unless the
 * data has changed so repetitive calls to this method is ok.
 */
hideHeadBangHudIcon(const id) {
	if (!xs_vec_equal(gfHeadBangHudIconColor[id], Float:{ 0.0, 0.0, 0.0 })) {
		message_begin(MSG_ONE, gMsgStatusIcon, { 0, 0, 0 }, id);
		write_byte(0);
		write_string(gszStatusIconSpriteName);
		write_byte(0);
		write_byte(0);
		write_byte(0);
		message_end();
		
		xs_vec_set(gfHeadBangHudIconColor[id], 0.0, 0.0, 0.0);
	}
}

/**
 * Trace downwards from the players head (EV_VEC_absmax[2]) in front of the player.
 */
traceDownInFrontOfPlayer(const id, const Float:vOrigin[3], const Float:vDirection[3], const Float:fAbsMin[3], const Float:fAbsMax[3], Float:vTraceEndPos[3]) {
	//calculate position that's forward from the player
	new Float:fOffsetX = vDirection[0] * gfForwardDist;
	new Float:fOffsetY = vDirection[1] * gfForwardDist;
	
	//trace downwards from in front of the player
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vOrigin[0] + fOffsetX, vOrigin[1] + fOffsetY, fAbsMax[2]);
	xs_vec_set(vTraceTo, vOrigin[0] + fOffsetX, vOrigin[1] + fOffsetY, fAbsMin[2] - 100.0);
	new trace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, trace);
	get_tr2(trace, TR_vecEndPos, vTraceEndPos);
}

/**
 * Trace backwards towards the player to get what they're standing on.
 */
bool:traceBackwardsTowardsPlayer(const id, const Float:vTraceStart[3], const Float:vDirection[3], const Float:fAbsMin[3], Float:vTraceEndPos[3], Float:vNormal[3]) {
	new Float:fOffsetX = vDirection[0] * -(gfForwardDist + 64.0);
	new Float:fOffsetY = vDirection[1] * -(gfForwardDist + 64.0);
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vTraceStart[0], vTraceStart[1], fAbsMin[2]);
	xs_vec_set(vTraceTo, vTraceStart[0] + fOffsetX, vTraceStart[1] + fOffsetY, fAbsMin[2]);
	new trace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, trace);
	
	//if the trace hit something
	new Float:fFraction;
	get_tr2(trace, TR_flFraction, fFraction);
	if (fFraction != 1.0) {
		//get the classname of the entity that was hit (typically what the player is standing on)
		new hitEnt = get_tr2(trace, TR_pHit);
		new bool:bHitBhopBlock = false;
		if (is_valid_ent(hitEnt)) {
			static szHitEntClassname[32];
			entity_get_string(hitEnt, EV_SZ_classname, szHitEntClassname, 32);
			bHitBhopBlock = (equal(szHitEntClassname, "func_door") != 0);
		}
		
		//ignore the hit entity if it's possibly a bhop block
		if (!bHitBhopBlock) {
			get_tr2(trace, TR_vecEndPos, vTraceEndPos);
			get_tr2(trace, TR_vecPlaneNormal, vNormal);
			
			//ensure the normal is parallel to the ground
			if (vNormal[2] != 0.0) {
				vNormal[2] = 0.0;
				xs_vec_normalize(vNormal, vNormal);
			}
			
			return true;
		}
	}
	
	return false;
}

/**
 * Trace forwards to get the jump distance.
 */
bool:traceForwardsForDistance(const id, const Float:vTraceFrom[3], const Float:vNormal[3], const Float:fLength, Float:vTraceEndPos[3]) {
	new Float:fOffsetX = (vNormal[0] * fLength);
	new Float:fOffsetY = (vNormal[1] * fLength);
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0] + fOffsetX, vTraceFrom[1] + fOffsetY, vTraceFrom[2]);
	new trace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, trace);
	
	//if the trace hit something
	new Float:fFraction;
	get_tr2(trace, TR_flFraction, fFraction);
	if (fFraction != 1.0) {
		get_tr2(trace, TR_vecEndPos, vTraceEndPos);
		return true;
	}
	
	return false;
}

/**
 * Trace downwards to get the height of the drop.
 */
Float:traceDownForDropHeight(const id, const Float:vTraceFrom[3]) {
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0], vTraceFrom[1], vTraceFrom[2] - 80);
	
	new trace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, trace);
	
	new Float:vTraceEndPos[3];
	get_tr2(trace, TR_vecEndPos, vTraceEndPos);
	return get_distance_f(vTraceFrom, vTraceEndPos);
}

/**
 * Trace above the player's head to detect headbangers.
 */
Float:traceAbovePlayerHead(const id, const Float:vOrigin[3], const Float:fViewOffset[3]) {
	static Float:vMins[3];
	static Float:vMaxs[3];
	entity_get_vector(id, EV_VEC_mins, vMins);
	entity_get_vector(id, EV_VEC_maxs, vMaxs);
	
	//calculate a smooth z coordinate using the viewoffset, then compensate for ducking
	static Float:z;
	z = (vOrigin[2] + fViewOffset[2] + (vMaxs[2] == 36.0 ? 19.0 : 6.0));
	
	static Float:vTraceFrom[3];
	static Float:vTraceTo[3];
	static trace = 0;
	for (new i = 0; i < 5; ++i) {
		if (i == 0) {		//centre
			xs_vec_set(vTraceFrom, vOrigin[0], vOrigin[1], z);
		} else if (i == 1) {	//front left
			xs_vec_set(vTraceFrom, vOrigin[0] + vMins[0], vOrigin[1] + vMaxs[1], z);
		} else if (i == 2) {	//front right
			xs_vec_set(vTraceFrom, vOrigin[0] + vMaxs[0], vOrigin[1] + vMaxs[1], z);
		} else if (i == 3) {	//back left
			xs_vec_set(vTraceFrom, vOrigin[0] + vMins[0], vOrigin[1] + vMins[1], z);
		} else if (i == 4) {	//back right
			xs_vec_set(vTraceFrom, vOrigin[0] + vMaxs[0], vOrigin[1] + vMins[1], z);
		}
		xs_vec_set(vTraceTo, vTraceFrom[0], vTraceFrom[1], vTraceFrom[2] + gfHeadBangTraceHeight);
		
		engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, trace);
		
		//if the trace hit something
		new Float:fFraction;
		get_tr2(trace, TR_flFraction, fFraction);
		if (fFraction != 1.0) {
			static Float:vTraceEndPos[3];
			get_tr2(trace, TR_vecEndPos, vTraceEndPos);
			return get_distance_f(vTraceFrom, vTraceEndPos);
		}
	}
	
	return 0.0;
}

/**
 * Show the distance aid for the given player.
 */
showDistance(const id, const Float:vFrom[3], const Float:vTo[3], const Float:vNormal[3], const distance, const Float:fColor[3]) {
	//create the entities used for the distance aid, if not already created
	if (gDistanceEnt[id] == 0) {
		new ent = Beam_Create(gszDotSprite, gfDistanceBeamWidth);
		entity_set_string(ent, EV_SZ_classname, gszDistanceClassname);	//to recognise the entity
		entity_set_int(ent, OWNER_INT, id);					//to know who it belongs to
		gDistanceEnt[id] = ent;
		
		//create 3 new entities to use for the distance digits
		for (new i = 0; i < 3; ++i) {
			ent = create_entity(gszInfoTarget);
			entity_set_string(ent, EV_SZ_classname, gszDigitClassname);	//to recognise the entity
			entity_set_model(ent, gszDigits);				//the digits sprite
			entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);	//to control the visibility
			entity_set_float(ent, EV_FL_renderamt, 255.0);			//start visible
			entity_set_vector(ent, EV_VEC_rendercolor, fColor);		//start with given color
			entity_set_float(ent, EV_FL_scale, 0.5);			//make half the size
			entity_set_int(ent, OWNER_INT, id);				//to know who it belongs to
			gDistanceValueEnts[id][i] = ent;
		}
	}
	
	//update the beam position and color
	Beam_PointsInit(gDistanceEnt[id], vFrom, vTo);
	Beam_SetColor(gDistanceEnt[id], fColor);
	
	//calculate position for digits (halfway along the beam) and show the digits
	new Float:fOffsetX = (vNormal[0] * (distance / 2.0));
	new Float:fOffsetY = (vNormal[1] * (distance / 2.0));
	new Float:vPosition[3]; 
	xs_vec_set(vPosition, vFrom[0] + fOffsetX, vFrom[1] + fOffsetY, vFrom[2]);
	setupDistanceDigits(gDistanceValueEnts[id], distance, vPosition, vNormal, fColor);
}

/**
 * Hide all entities used for the distance aid for the given player.
 */
hideDistance(const id) {
	if (gDistanceEnt[id] != 0) {
		remove_entity(gDistanceEnt[id]);
		gDistanceEnt[id] = 0;
		
		for (new i = 0; i < 3; ++i) {
			remove_entity(gDistanceValueEnts[id][i]);
			gDistanceValueEnts[id][i] = 0;
		}
	}
}

/**
 * Show the jump edge aid for the given player.
 */
showJumpEdge(const id, const Float:vEdgePos[3], const Float:vNormal[3], const bool:bIsHj, const Float:fLength) {
	//create the entity used for the jump edge aid, if not already created
	if (gJumpEdgeEnt[id] == 0) {
		new ent = Beam_Create(gszDotSprite, gfJumpEdgeBeamWidth);
		entity_set_string(ent, EV_SZ_classname, gszJumpEdgeClassname);		//to recognise the entity
		entity_set_int(ent, OWNER_INT, id);					//to know who it belongs to
		gJumpEdgeEnt[id] = ent;
	}
	
	new Float:vOrigin[3];
	if (bIsHj) {
		vOrigin[0] = vEdgePos[0] + (-vNormal[0] * 13.0);
		vOrigin[1] = vEdgePos[1] + (-vNormal[1] * 13.0);
	} else {
		vOrigin[0] = vEdgePos[0];
		vOrigin[1] = vEdgePos[1];
	}
	vOrigin[2] = vEdgePos[2] + 0.2;
	
	new Float:fHalfLength = (fLength / 2.0);
	
	new Float:vFrom[3];
	vFrom[0] = vOrigin[0] + (-vNormal[1] * fHalfLength);
	vFrom[1] = vOrigin[1] + ( vNormal[0] * fHalfLength);
	vFrom[2] = vOrigin[2];
	
	new Float:vTo[3];
	vTo[0] = vOrigin[0] + ( vNormal[1] * fHalfLength);
	vTo[1] = vOrigin[1] + (-vNormal[0] * fHalfLength);
	vTo[2] = vOrigin[2];
	
	Beam_PointsInit(gJumpEdgeEnt[id], vFrom, vTo); 
	Beam_SetColor(gJumpEdgeEnt[id], (bIsHj ? gfColorHj : gfColorLj));
}

/**
 * Hide the jump edge aid for the given player.
 */
hideJumpEdge(const id) {
	if (gJumpEdgeEnt[id] != 0) {
		remove_entity(gJumpEdgeEnt[id]);
		gJumpEdgeEnt[id] = 0;
	}
}

/**
 * Setup and show the sprites used for the distance digits.
 */
setupDistanceDigits(const digits[3], const distance, const Float:vOrigin[3], const Float:vNormal[3], const Float:fColor[3]) {
	new const Float:fDigitGapSize = 10.0;
	new Float:vPos[3];
	
	//create string from distance value
	new szDistance[4];
	format(szDistance, 3, "%d", distance);
	
	//get the angles the digits will be at, based off the given normal
	new Float:vAngles[3];
	vector_to_angle(vNormal, vAngles);
	
	new numDigits = strlen(szDistance);
	for (new i = 0; i < numDigits; ++i) {
		entity_set_float(digits[i], EV_FL_frame, float(szDistance[i] - 48));
		
		if (i == 0) {
			vPos[0] = vOrigin[0] + (-vNormal[1] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
			vPos[1] = vOrigin[1] + ( vNormal[0] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
		} else if (i == 1) {
			vPos[0] = vOrigin[0] + ( vNormal[1] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
			vPos[1] = vOrigin[1] + ( vNormal[0] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
		} else {
			vPos[0] = vOrigin[0] + ( vNormal[1] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
			vPos[1] = vOrigin[1] + (-vNormal[0] * fDigitGapSize * gfDigitOffsetMultipliers[i]);
		}
		vPos[2] = vOrigin[2] + 8.0;
		
		entity_set_origin(digits[i], vPos);
		entity_set_vector(digits[i], EV_VEC_angles, vAngles);
		entity_set_vector(digits[i], EV_VEC_rendercolor, fColor);
	}
}

/**
 * Re-maps a number from one range to another.
 */
Float:map(const Float:fVal, const Float:fInMin, const Float:fInMax, const Float:fOutMin, const Float:fOutMax) {
	return (fVal - fInMin) * (fOutMax - fOutMin) / (fInMax - fInMin) + fOutMin;
}

/**
 * Print chat messages to given user with color.
 */
client_printc(const id, const print, const szMessage[], const {Float,Sql,Result,_}:...) {
	static szMsg[193];
	vformat(szMsg, 192, szMessage, 4);
	
	if (print == print_chat) {
		new cWhite[2] = {0x01, 0};
		new cTeam[2] = {0x03, 0};
		new cGreen[2] = {0x04, 0};
		
		replace_all(szMsg, 192, "!w", cWhite);
		replace_all(szMsg, 192, "!t", cTeam);
		replace_all(szMsg, 192, "!g", cGreen);
		
		if (id > 0 && id <= gMaxPlayers) {
			if (is_user_connected(id)) {
				message_begin(MSG_ONE, gMsgSayText, {0, 0, 0}, id);
				write_byte(id);
				write_string(szMsg);
				message_end();
			}
		} else if (id == 0) {
			for (new i = 1; i <= gMaxPlayers; i++) {
				if (is_user_connected(i)) {
					message_begin(MSG_ONE, gMsgSayText, {0, 0, 0}, i);
					write_byte(i);
					write_string(szMsg);
					message_end();
				}
			}
		}
	} else {
		replace_all(szMsg, 192, "!t", "");
		replace_all(szMsg, 192, "!g", "");
		replace_all(szMsg, 192, "!w", "");
		client_printc(id, print, szMsg);
	}
}
