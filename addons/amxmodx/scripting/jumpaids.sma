#include <amxmodx>
#include <engine>
#include <fakemeta>

#include "beams.inc"

#define PLUGIN "Jump Aids"
#define VERSION "1.0"
#define AUTHOR "Necro"

#pragma semicolon 1;

//constants
new const gszPrefix[] = "!w[!tJUMPAIDS!w] !g";
new const gszJumpAidsPrefix[] = "jumpaids";
new const gszJumpAidsMainMenu[] = "jumpaids_mainmenu";
new const gszInfoTarget[] = "info_target";
new const gszDigitClassname[] = "jumpaids_digit";
new const gszDistanceBeamClassname[] = "jumpaids_distancebeam";
new const gszJumpEdgeBeamClassname[] = "jumpaids_jumpedgebeam";
new const gszDotSprite[] = "sprites/jumpaids/dot.spr";
new const gszDigits[] = "sprites/jumpaids/digits.spr";
new const Float:gfDigitOffsetMultipliers[3] = { 0.8, 0.0, 0.8 };
new const Float:gColorLj[3] = { 0.0, 255.0, 0.0 };
new const Float:gColorHj[3] = { 200.0, 80.0, 0.0 };
new const Float:gForwardDist = 100.0;		//how far forward the initial trace will start from
new const Float:gMinLjLength = 100.0;		//minimum length of LJ allowed for distance to be shown
new const Float:gMaxLjLength = 300.0;		//maximum allowed LJ length
new const Float:gJumpEdgeBeamLength = 60.0;	//length of the jump edge beam
new const Float:gJumpEdgeBeamWidth = 1.0;	//width of the jump edge beam
new const Float:gDistanceBeamWidth = 2.0;	//width of the distance beam
new const OWNER_INT = EV_INT_iuser4;

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
new gDistanceBeam[33];
new gJumpEdgeBeam[33];
new gDistanceDigits[33][3];
new gszMainMenu[256];
new gKeysMainMenu;
new bool:gDistanceBeamOn[33];
new bool:gJumpEdgeBeamOn[33];
new bool:gMainMenuOpen[33];

public plugin_precache() {
	precache_model(gszDotSprite);
	precache_model(gszDigits);
}

public plugin_init() {
	//register plugin are server variable so servers running this plugin can be searched for
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_cvar(PLUGIN, VERSION, FCVAR_SERVER, 0.0);
	
	//register forwards
	register_forward(FM_AddToFullPack, "addToFullPack", 1);
	
	//register client commands
	register_clcmd("togglejumpaids", "toggleAllJumpAids");
	register_clcmd("jumpaids", "showMainMenu");
	register_clcmd("say /jumpaids", "showMainMenu");
	
	//register CVARs
	register_cvar("jumpaids_defaulton", "1");	//default condition - all players start with aids! :D
	
	//create main menu
	new size = sizeof(gszMainMenu);
	add(gszMainMenu, size, "\yJump Aids Main Menu^n^n");
	add(gszMainMenu, size, "\r1. \wDistance: %s^n");
	add(gszMainMenu, size, "\r2. \wEdge: %s^n^n");
	add(gszMainMenu, size, "\r0. \wClose");
	gKeysMainMenu = B1 | B2 | B0;
	register_menucmd(register_menuid(gszJumpAidsMainMenu), gKeysMainMenu, "handleMainMenu");
}

public plugin_cfg() {
	//set maximum number of players
	gMaxPlayers = get_maxplayers();
	
	//get say text message ID
	gMsgSayText = get_user_msgid("SayText");
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
	if (get_cvar_num("jumpaids_defaulton") > 0) {
		gDistanceBeamOn[id] = true;
		gJumpEdgeBeamOn[id] = true;
	}
	gMainMenuOpen[id] = false;
}

public client_disconnect(id) {
	hideDistanceBeam(id);
	hideJumpEdgeBeam(id);
	gDistanceBeamOn[id] = false;
	gJumpEdgeBeamOn[id] = false;
	gMainMenuOpen[id] = false;
}

public toggleAllJumpAids(id) {
	new bool:bIsAJumpAidDisabled = (!gDistanceBeamOn[id] || !gJumpEdgeBeamOn[id]);
	if (bIsAJumpAidDisabled) {
		//enable all jump aids that are currently disabled
		if (!gDistanceBeamOn[id]) {
			gDistanceBeamOn[id] = true;
		}
		
		if (!gJumpEdgeBeamOn[id]) {
			gJumpEdgeBeamOn[id] = true;
		}
		
		client_printc(id, print_chat, "%sAll jump aids enabled.", gszPrefix);
	} else {
		//disable all jump aids that are currently enabled
		if (gDistanceBeamOn[id]) {
			gDistanceBeamOn[id] = false;
		}
		
		if (gJumpEdgeBeamOn[id]) {
			gJumpEdgeBeamOn[id] = false;
		}
		
		client_printc(id, print_chat, "%sAll jump aids disabled.", gszPrefix);
	}
	
	//refresh main menu if it's open
	if (gMainMenuOpen[id]) {
		showMainMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

public showMainMenu(id) {
	//format the main menu
	static szMenu[256];
	static szDistanceState[6];
	static szJumpEdgeState[6];
	szDistanceState = (gDistanceBeamOn[id] ? "\yOn" : "\rOff");
	szJumpEdgeState = (gJumpEdgeBeamOn[id] ? "\yOn" : "\rOff");
	format(szMenu, 256, gszMainMenu, szDistanceState, szJumpEdgeState);
	
	//show the main menu to the player
	show_menu(id, gKeysMainMenu, szMenu, -1, gszJumpAidsMainMenu);
	gMainMenuOpen[id] = true;
	
	return PLUGIN_HANDLED;
}

public handleMainMenu(id, num) {
	switch (num) {
		case N1: {
			gDistanceBeamOn[id] = !gDistanceBeamOn[id];
			client_printc(id, print_chat, "%sDistance jump aid %sabled.", gszPrefix, (gDistanceBeamOn[id] ? "en" : "dis"));
		}
		case N2: {
			gJumpEdgeBeamOn[id] = !gJumpEdgeBeamOn[id];
			client_printc(id, print_chat, "%sEdge jump aid %sabled.", gszPrefix, (gJumpEdgeBeamOn[id] ? "en" : "dis"));
		}
		case N0: {
			gMainMenuOpen[id] = false;
			return;
		}
	}
	
	//display menu again
	showMainMenu(id);
	gMainMenuOpen[id] = true;
}

/**
 * Test if given entity is a valid JumpAids entity.
 */
bool:isJumpAidsEntity(ent) {
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
bool:isSpectating(id, targetId) {
	new specId = entity_get_int(id, EV_INT_iuser2);
	return (targetId == specId);
}

/**
 * Do various traces to get and show the jump information.
 */
handleJumpAids(id) {
	static iFlags;
	static bool:bDistanceBeamVisible;
	static bool:bJumpEdgeBeamVisible;
	static bool:bJumpAidEnabled;
	
	iFlags = entity_get_int(id, EV_INT_flags);
	bDistanceBeamVisible = false;
	bJumpEdgeBeamVisible = false;
	bJumpAidEnabled = (gDistanceBeamOn[id] || gJumpEdgeBeamOn[id]);
	
	//if player is alive, has feet on the ground and has a jump aid enabled
	if (is_user_alive(id) && (iFlags & FL_ONGROUND) && bJumpAidEnabled) {
		static Float:vTraceEndPos[3];
		static Float:heightDelta;
		static Float:vPlayerOrigin[3];
		static Float:vPlayerDirection[3];
		static Float:fPlayerAbsMin[3];
		static Float:fPlayerAbsMax[3];
		static Float:fPlayerAngles[3];
		
		//get player vectors of interest
		entity_get_vector(id, EV_VEC_origin, vPlayerOrigin);
		entity_get_vector(id, EV_VEC_absmin, fPlayerAbsMin);
		entity_get_vector(id, EV_VEC_absmax, fPlayerAbsMax);
		entity_get_vector(id, EV_VEC_angles, fPlayerAngles);
		fPlayerAbsMin[2] += 0.9;	//needs doing, dunno why...
		
		//calculate unit vector for the direction the player is facing - the yaw only
		xs_vec_set(vPlayerDirection, floatcos(fPlayerAngles[1], degrees), floatsin(fPlayerAngles[1], degrees), 0.0);
		
		//trace down in front of player, don't care if it hits anything or not
		traceDownInFrontOfPlayer(id, vPlayerOrigin, vPlayerDirection, fPlayerAbsMin, fPlayerAbsMax, vTraceEndPos);
		
		//get height difference between trace end point and players feet
		heightDelta = (fPlayerAbsMin[2] - vTraceEndPos[2]);
		if (heightDelta > 8.0) {
			static Float:vJumpEdge[3];
			static Float:vNormal[3];
			static bool:bHit;
			
			bHit = traceBackwardsTowardsPlayer(id, vTraceEndPos, vPlayerDirection, fPlayerAbsMin, vJumpEdge, vNormal);
			if (bHit) {
				static Float:fHeight;
				static bool:isHj;
				
				fHeight = traceDownForDropHeight(id, vJumpEdge);
				isHj = (fHeight > 69.5);
				
				if (gJumpEdgeBeamOn[id]) {
					showJumpEdgeBeam(id, vJumpEdge, vNormal, isHj, gJumpEdgeBeamLength);
					bJumpEdgeBeamVisible = true;
				}
				
				if (gDistanceBeamOn[id]) {
					bHit = traceForwardsForDistance(id, vJumpEdge, vNormal, gMaxLjLength, vTraceEndPos);
					if (bHit) {
						static Float:fDistance;
						static iDistance;
						
						fDistance = get_distance_f(vJumpEdge, vTraceEndPos);
						iDistance = floatround(fDistance, floatround_round);
						
						if (iDistance >= gMinLjLength) {
							showDistanceBeam(id, vJumpEdge, vTraceEndPos, vNormal, iDistance, (isHj ? gColorHj : gColorLj));
							bDistanceBeamVisible = true;
						}
					}
				}
			}
		}
	}

	//hide the distance beam and digit sprites if they weren't updated
	if (!bDistanceBeamVisible) {
		hideDistanceBeam(id);
	}

	//hide the jump-edge beam if it wasn't updated
	if (!bJumpEdgeBeamVisible) {
		hideJumpEdgeBeam(id);
	}
}

/**
 * Trace downwards from the players head (EV_VEC_absmax[2]) in front of the player.
 */
traceDownInFrontOfPlayer(id, const Float:vOrigin[3], const Float:vDirection[3], const Float:fAbsMin[3], const Float:fAbsMax[3], Float:vTraceEndPos[3]) {
	//calculate position that's forward from the player
	new Float:fOffsetX = vDirection[0] * gForwardDist;
	new Float:fOffsetY = vDirection[1] * gForwardDist;
	
	//trace downwards from in front of the player
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vOrigin[0] + fOffsetX, vOrigin[1] + fOffsetY, fAbsMax[2]);
	xs_vec_set(vTraceTo, vOrigin[0] + fOffsetX, vOrigin[1] + fOffsetY, fAbsMin[2] - 100.0);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
}

/**
 * Trace backwards towards the player to get what they're standing on.
 */
bool:traceBackwardsTowardsPlayer(id, const Float:vTraceStart[3], const Float:vDirection[3], const Float:fAbsMin[3], Float:vTraceEndPos[3], Float:vNormal[3]) {
	new Float:fOffsetX = vDirection[0] * -(gForwardDist + 64.0);
	new Float:fOffsetY = vDirection[1] * -(gForwardDist + 64.0);
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vTraceStart[0], vTraceStart[1], fAbsMin[2]);
	xs_vec_set(vTraceTo, vTraceStart[0] + fOffsetX, vTraceStart[1] + fOffsetY, fAbsMin[2]);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	
	//if the trace hit something
	new Float:fFraction;
	get_tr2(iTrace, TR_flFraction, fFraction);
	if (fFraction != 1.0) {
		//get the classname of the entity that was hit (typically what the player is standing on)
		new hitEnt = get_tr2(iTrace, TR_pHit);
		static szHitEntClassname[32];
		if (is_valid_ent(hitEnt)) {
			entity_get_string(hitEnt, EV_SZ_classname, szHitEntClassname, 32);
		}
		
		//ignore the hit entity if it's a door - possibly a bhop block
		if (!is_valid_ent(hitEnt) || !equal(szHitEntClassname, "func_door")) {
			get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
			get_tr2(iTrace, TR_vecPlaneNormal, vNormal);
			
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
bool:traceForwardsForDistance(id, const Float:vTraceFrom[3], const Float:vNormal[3], const Float:fLength, Float:vTraceEndPos[3]) {
	new Float:fOffsetX = (vNormal[0] * fLength);
	new Float:fOffsetY = (vNormal[1] * fLength);
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0] + fOffsetX, vTraceFrom[1] + fOffsetY, vTraceFrom[2]);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	
	//if the trace hit something
	new Float:fFraction;
	get_tr2(iTrace, TR_flFraction, fFraction);
	if (fFraction != 1.0) {
		get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
		return true;
	}
	
	return false;
}

/**
 * Trace downwards to get the height of the drop.
 */
Float:traceDownForDropHeight(id, const Float:vTraceFrom[3]) {
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0], vTraceFrom[1], vTraceFrom[2] - 80);
	
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	
	new Float:vTraceEndPos[3];
	get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
	return get_distance_f(vTraceFrom, vTraceEndPos);
}

/**
 * Show the distance beam and distance sprites for the given player..
 */
showDistanceBeam(id, const Float:vFrom[3], const Float:vTo[3], const Float:vNormal[3], const iDistance, const Float:color[3]) {
	//create the entities used for the distance beam, if not already created
	if (gDistanceBeam[id] == 0) {
		//create distance beam entity
		new ent = Beam_Create(gszDotSprite, gDistanceBeamWidth);
		entity_set_string(ent, EV_SZ_classname, gszDistanceBeamClassname);	//to recognise the entity
		entity_set_int(ent, OWNER_INT, id);					//to know who it belongs to
		gDistanceBeam[id] = ent;
		
		//create 3 new entities to use for the distance digits
		for (new i = 0; i < 3; ++i) {
			ent = create_entity(gszInfoTarget);
			entity_set_string(ent, EV_SZ_classname, gszDigitClassname);	//to recognise the entity
			entity_set_model(ent, gszDigits);				//the digits sprite
			entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);	//to control the visibility
			entity_set_float(ent, EV_FL_renderamt, 255.0);			//start visible
			entity_set_vector(ent, EV_VEC_rendercolor, color);		//start with given color
			entity_set_float(ent, EV_FL_scale, 0.5);			//make half the size
			entity_set_int(ent, OWNER_INT, id);				//to know who it belongs to
			gDistanceDigits[id][i] = ent;
		}
	}
	
	//update the beam position and color
	Beam_PointsInit(gDistanceBeam[id], vFrom, vTo);
	Beam_SetColor(gDistanceBeam[id], color);
	
	//calculate position for digits (halfway along the beam) and show the digits
	new Float:fOffsetX = (vNormal[0] * (iDistance / 2.0));
	new Float:fOffsetY = (vNormal[1] * (iDistance / 2.0));
	new Float:vPosition[3]; 
	xs_vec_set(vPosition, vFrom[0] + fOffsetX, vFrom[1] + fOffsetY, vFrom[2]);
	setupDistanceDigits(gDistanceDigits[id], iDistance, vPosition, vNormal, color);
}

/**
 * Delete all entities used for the distance beam for the given player.
 */
hideDistanceBeam(id) {
	if (gDistanceBeam[id] != 0) {
		remove_entity(gDistanceBeam[id]);
		gDistanceBeam[id] = 0;
	}
	
	for (new i = 0; i < 3; ++i) {
		remove_entity(gDistanceDigits[id][i]);
		gDistanceDigits[id][i] = 0;
	}
}

/**
 * Show the jump edge beam for the given player.
 */
showJumpEdgeBeam(id, const Float:vEdgePos[3], const Float:vNormal[3], const bool:isHj, const Float:length) {
	//create the entity used for the jump edge beam, if not already created
	if (gJumpEdgeBeam[id] == 0) {
		//create jump edge beam entity
		new ent = Beam_Create(gszDotSprite, gJumpEdgeBeamWidth);
		entity_set_string(ent, EV_SZ_classname, gszJumpEdgeBeamClassname);	//to recognise the entity
		entity_set_int(ent, OWNER_INT, id);					//to know who it belongs to
		gJumpEdgeBeam[id] = ent;
	}
	
	new Float:vOrigin[3];
	if (isHj) {
		vOrigin[0] = vEdgePos[0] + (-vNormal[0] * 13.0);
		vOrigin[1] = vEdgePos[1] + (-vNormal[1] * 13.0);
	} else {
		vOrigin[0] = vEdgePos[0];
		vOrigin[1] = vEdgePos[1];
	}
	vOrigin[2] = vEdgePos[2] + 0.2;
	
	new Float:halfLength = (length / 2.0);
	
	new Float:vFrom[3];
	vFrom[0] = vOrigin[0] + (-vNormal[1] * halfLength);
	vFrom[1] = vOrigin[1] + ( vNormal[0] * halfLength);
	vFrom[2] = vOrigin[2];
	
	new Float:vTo[3];
	vTo[0] = vOrigin[0] + ( vNormal[1] * halfLength);
	vTo[1] = vOrigin[1] + (-vNormal[0] * halfLength);
	vTo[2] = vOrigin[2];
	
	Beam_PointsInit(gJumpEdgeBeam[id], vFrom, vTo); 
	Beam_SetColor(gJumpEdgeBeam[id], (isHj ? gColorHj : gColorLj));
}

/**
 * Delete the jump edge entity for the given player.
 */
hideJumpEdgeBeam(id) {
	if (gJumpEdgeBeam[id] != 0) {
		remove_entity(gJumpEdgeBeam[id]);
		gJumpEdgeBeam[id] = 0;
	}
}

/**
 * Setup and show the sprites used for the distance digits.
 */
setupDistanceDigits(const digits[3], const distance, const Float:vOrigin[3], const Float:vNormal[3], const Float:color[3]) {
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
		entity_set_vector(digits[i], EV_VEC_rendercolor, color);
	}
}

/**
 * Print chat messages to given user with color.
 */
client_printc(id, print, const szMessage[], {Float,Sql,Result,_}:...) {
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
