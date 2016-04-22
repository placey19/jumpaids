#include <amxmodx>
#include <engine>
#include <fakemeta>

#include "beams.inc"

#define PLUGIN "Jump Aids"
#define VERSION "1.0"
#define AUTHOR "Necro"

#pragma semicolon 1;

new const gszJumpAidsPrefix[] = "jumpaids";
new const gszInfoTarget[] = "info_target";
new const gszDigitClassname[] = "jumpaids_digit";
new const gszDistanceBeamClassname[] = "jumpaids_distancebeam";
new const gszJumpEdgeBeamClassname[] = "jumpaids_jumpedgebeam";
new const gszDotSprite[] = "sprites/jumpaids/dot.spr";
new const gszDigits[] = "sprites/jumpaids/digits.spr";

//constants
new const Float:gfDigitOffsetMultipliers[3] = { 0.8, 0.0, 0.8 };
new const Float:gColor0[3] = { 0.0, 0.0, 0.0 };
new const Float:gColorLj[3] = { 0.0, 255.0, 0.0 };
new const Float:gColorHj[3] = { 200.0, 80.0, 0.0 };
new const Float:gForwardDist = 100.0;		//how far forward the initial trace will start from
new const Float:gMinLjLength = 100.0;		//minimum length of LJ allowed for distance to be shown
new const Float:gMaxLjLength = 300.0;		//maximum allowed LJ length
new const Float:gJumpEdgeBeamLength = 60.0;	//length of the jump edge beam
new const Float:gJumpEdgeBeamWidth = 1.0;	//width of the jump edge beam
new const Float:gDistanceBeamWidth = 2.0;	//width of the distance beam

new giMaxPlayers;
new gDistanceBeam[33];
new gJumpEdgeBeam[33];
new gDistanceDigits[33][3];

//reusable expressions for all players
new Float:gvPlayerOrigin[3];
new Float:gvPlayerDirection[3];
new Float:gfPlayerAbsMin[3];
new Float:gfPlayerAbsMax[3];
new Float:gfPlayerAngles[3];

public plugin_precache() {
	precache_model(gszDotSprite);
	precache_model(gszDigits);
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);
	register_forward(FM_AddToFullPack, "addToFullPack");
}

public plugin_cfg() {
	giMaxPlayers = get_maxplayers();

	for (new id = 1; id <= giMaxPlayers; id++) {
		//create distance beam entity
		new ent = Beam_Create(gszDotSprite, gDistanceBeamWidth);
		entity_set_string(gDistanceBeam[id], EV_SZ_classname, gszDistanceBeamClassname);
		entity_set_int(gDistanceBeam[id], EV_INT_groupinfo, id);
		gDistanceBeam[id] = ent;
		
		//create jump edge beam entity
		ent = Beam_Create(gszDotSprite, gJumpEdgeBeamWidth);
		entity_set_string(gJumpEdgeBeam[id], EV_SZ_classname, gszJumpEdgeBeamClassname);
		entity_set_int(gJumpEdgeBeam[id], EV_INT_groupinfo, id);
		gJumpEdgeBeam[id] = ent;
		
		//create 3 new entities to use for the distance digits
		for (new i = 0; i < 3; ++i) {
			ent = create_entity(gszInfoTarget);
			entity_set_string(ent, EV_SZ_classname, gszDigitClassname);
			entity_set_model(ent, gszDigits);
			entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);
			entity_set_float(ent, EV_FL_renderamt, 0.0);
			entity_set_vector(ent, EV_VEC_rendercolor, gColor0);
			entity_set_float(ent, EV_FL_scale, 0.5);
			entity_set_int(ent, EV_INT_groupinfo, id);
			gDistanceDigits[id][i] = ent;
		}
	}
}

public client_PreThink(id) {
	showJumpAids(id);
}

public addToFullPack(ent_state, ent, edict_t_ent, id, hostflags, player, pSet) {
	if (is_user_connected(id) && isJumpAidsEntity(ent)) {
		new entOwner = entity_get_int(ent, EV_INT_groupinfo);
		if (id != entOwner) {
			entity_set_float(ent, EV_FL_renderamt, 0.0);
			return 0;
		}
	}
	
	return 1;
}

/**
 * Test if given entity is a valid JumpAids entity.
 */
bool:isJumpAidsEntity(ent) {
	if (is_valid_ent(ent)) {
		static gszClassname[32];
		entity_get_string(ent, EV_SZ_classname, gszClassname, 32);
		
		//test length to prevent strfind on smaller classname (14 chars is the smallest jumpaids classname)
		if (strlen(gszClassname) >= 14 && strfind(gszClassname, gszJumpAidsPrefix) != -1) {
			return true;
		}
	}
	
	return false;
}

/**
 * Do various traces to get and show the jump information.
 */
showJumpAids(id) {
	static iFlags;
	static bool:bUpdatedDistanceBeam;
	static bool:bUpdatedJumpEdgeBeam;
	
	iFlags = entity_get_int(id, EV_INT_flags);
	bUpdatedDistanceBeam = false;
	bUpdatedJumpEdgeBeam = false;
	
	//if player is alive and has feet on the ground
	if (is_user_alive(id) && iFlags & FL_ONGROUND) {
		static Float:vTraceEndPos[3];
		static Float:heightDelta;
		
		//get player vectors of interest
		entity_get_vector(id, EV_VEC_origin, gvPlayerOrigin);
		entity_get_vector(id, EV_VEC_absmin, gfPlayerAbsMin);
		entity_get_vector(id, EV_VEC_absmax, gfPlayerAbsMax);
		entity_get_vector(id, EV_VEC_angles, gfPlayerAngles);
		gfPlayerAbsMin[2] += 0.9;	//needs doing, dunno why...
		
		//calculate unit vector for the direction the player is facing - the yaw
		xs_vec_set(gvPlayerDirection, floatcos(gfPlayerAngles[1], degrees), floatsin(gfPlayerAngles[1], degrees), 0.0);
		
		//trace down in front of player, don't care if it hits anything or not
		traceDownInFrontOfPlayer(id, vTraceEndPos);
		
		//get height difference between trace end point and players feet
		heightDelta = (gfPlayerAbsMin[2] - vTraceEndPos[2]);
		if (heightDelta > 8.0) {
			static Float:vJumpEdge[3];
			static Float:vNormal[3];
			static bool:bHit;
			
			bHit = traceBackwardsTowardsPlayer(id, vTraceEndPos, vJumpEdge, vNormal);
			if (bHit) {
				static Float:fHeight;
				static bool:isHj;
				
				fHeight = traceDownForDropHeight(id, vJumpEdge);
				isHj = (fHeight > 69.5);
				showJumpEdgeBeam(id, vJumpEdge, vNormal, isHj, gJumpEdgeBeamLength);
				bUpdatedJumpEdgeBeam = true;
				
				bHit = traceForwardsForDistance(id, vJumpEdge, vNormal, gMaxLjLength, vTraceEndPos);
				if (bHit) {
					static Float:fDistance;
					static iDistance;
					
					fDistance = get_distance_f(vJumpEdge, vTraceEndPos);
					iDistance = floatround(fDistance, floatround_round);
					
					if (iDistance >= gMinLjLength) {
						showDistanceBeam(id, vJumpEdge, vTraceEndPos, vNormal, iDistance, (isHj ? gColorHj : gColorLj));
//						console_print(id, "fHeight: %f", fHeight);
						bUpdatedDistanceBeam = true;
					}
				}
			}
		}
	}

	//hide the distance beam and digit sprites if they weren't updated
	if (!bUpdatedDistanceBeam) {
		hideDistanceBeam(id);
	}

	//hide the jump-edge beam if it wasn't updated
	if (!bUpdatedJumpEdgeBeam) {
		hideJumpEdgeBeam(id);
	}
}

/**
 * Trace downwards from the players head (EV_VEC_absmax[2]) in front of the player.
 */
traceDownInFrontOfPlayer(id, Float:vTraceEndPos[3]) {
	//calculate position that's forward from the player
	new Float:fOffsetX = gvPlayerDirection[0] * gForwardDist;
	new Float:fOffsetY = gvPlayerDirection[1] * gForwardDist;
	
	//trace downwards from in front of the player
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, gvPlayerOrigin[0] + fOffsetX, gvPlayerOrigin[1] + fOffsetY, gfPlayerAbsMax[2]);
	xs_vec_set(vTraceTo, gvPlayerOrigin[0] + fOffsetX, gvPlayerOrigin[1] + fOffsetY, gfPlayerAbsMin[2] - 100.0);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
}

/**
 * Trace backwards towards the player to get what they're standing on.
 */
bool:traceBackwardsTowardsPlayer(id, const Float:vTraceStart[3], Float:vTraceEndPos[3], Float:vNormal[3]) {
	new Float:fOffsetX = gvPlayerDirection[0] * -(gForwardDist + 10.0);
	new Float:fOffsetY = gvPlayerDirection[1] * -(gForwardDist + 10.0);
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vTraceStart[0], vTraceStart[1], gfPlayerAbsMin[2]);
	xs_vec_set(vTraceTo, vTraceStart[0] + fOffsetX, vTraceStart[1] + fOffsetY, gfPlayerAbsMin[2]);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	
	//if the trace hit something
	new Float:fFraction;
	get_tr2(iTrace, TR_flFraction, fFraction);
	if (fFraction != 1.0) {
		get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
		get_tr2(iTrace, TR_vecPlaneNormal, vNormal);
		
		//ensure the normal is parallel to the ground
		if (vNormal[2] != 0.0) {
			vNormal[2] = 0.0;
			xs_vec_normalize(vNormal, vNormal);
		}
		
		return true;
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
 * Show the distance beam and distance sprites.
 */
showDistanceBeam(id, const Float:vFrom[3], const Float:vTo[3], const Float:vNormal[3], const iDistance, const Float:color[3]) {
	//update the beam position and color
	Beam_PointsInit(gDistanceBeam[id], vFrom, vTo);
	Beam_SetColor(gDistanceBeam[id], color);
	
	//calculate position for digits (halfway along the beam) and show the digits
	new Float:fOffsetX = (vNormal[0] * (iDistance / 2.0));
	new Float:fOffsetY = (vNormal[1] * (iDistance / 2.0));
	new Float:vPosition[3]; 
	xs_vec_set(vPosition, vFrom[0] + fOffsetX, vFrom[1] + fOffsetY, vFrom[2]);
	showDistanceDigits(id, gDistanceDigits[id], iDistance, vPosition, vNormal, color);
}

/**
 * Hide the distance beam and distance sprites.
 */
hideDistanceBeam(id) {
	Beam_SetColor(gDistanceBeam[id], gColor0);
	for (new i = 0; i < 3; ++i) {
		entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 0.0);
	}
}

/**
 * Show the jump edge beam.
 */
showJumpEdgeBeam(id, const Float:vEdgePos[3], const Float:vNormal[3], const bool:isHj, const Float:length) {
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

hideJumpEdgeBeam(id) {
	Beam_SetColor(gJumpEdgeBeam[id], gColor0);
}

/**
 * Setup and show the sprites used for the distance digits.
 */
showDistanceDigits(id, const digits[3], const distance, const Float:vOrigin[3], const Float:vNormal[3], const Float:color[3]) {
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
		if (is_valid_ent(digits[i])) {
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
		}
	}
	
	//set the color and visibility of the digits
	for (new i = 0; i < 3; ++i) {
		entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 255.0);
		entity_set_vector(gDistanceDigits[id][i], EV_VEC_rendercolor, color);
	}
}
