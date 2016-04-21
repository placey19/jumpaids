#include <amxmodx>
#include <engine>
#include <fakemeta>

#include "beams.inc"

#define PLUGIN "Jump Aids"
#define VERSION "1.0"
#define AUTHOR "Necro"

#pragma semicolon 1;

new const gszInfoTarget[] = "info_target";
new const gszDigitClassname[] = "jumpaids_digit";
new const gszDotSprite[] = "sprites/dot.spr";
new const gszDigits[] = "sprites/jumpaids/digits.spr";

new const Float:gfDigitOffsetMultipliers[3] = { 0.8, 0.0, 0.8 };
new const Float:gvColor0[3] = { 0.0, 0.0, 0.0 };
new const Float:gvColorLj[3] = { 0.0, 255.0, 0.0 };
new const Float:gvColorHj[3] = { 200.0, 100.0, 0.0 };

new giMaxPlayers;
new gDistanceBeam[33];
new gDistanceDigits[33][3];

//reusable expressions for all players
new Float:gfOffsetUnitX;
new Float:gfOffsetUnitY;
new Float:gfOffsetX;
new Float:gfOffsetY;
new Float:gvOrigin[3];
new Float:gvAbsMin[3];
new Float:gvAbsMax[3];
new Float:gvAngles[3];

//how far forward the initial trace will start from
new const Float:gForwardDist = 100.0;

public plugin_precache() {
	precache_model(gszDotSprite);
	precache_model(gszDigits);
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_cfg() {
	giMaxPlayers = get_maxplayers();

	for (new id = 1; id <= giMaxPlayers; id++) {
		gDistanceBeam[id] = Beam_Create(gszDotSprite, 2.0);
		
		//create 3 new entities to use for the distance digits
		for (new i = 0; i < 3; ++i) {
			new ent = create_entity(gszInfoTarget);
			if (is_valid_ent(ent)) {
				entity_set_string(ent, EV_SZ_classname, gszDigitClassname);
				entity_set_model(ent, gszDigits);
				entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);
				entity_set_float(ent, EV_FL_renderamt, 0.0);
				entity_set_vector(ent, EV_VEC_rendercolor, gvColor0);
				entity_set_float(ent, EV_FL_scale, 0.5);
			}
			gDistanceDigits[id][i] = ent;
		}
	}
}

public client_PreThink(id) {
	traceAndShowJumpDistance(id);
}

set_distance_digits(const digits[3], const distance, const Float:vOrigin[3], Float:vNormal[3]) {
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
}

/**
 * Trace downwards from the players head (EV_VEC_absmax[2]) in front of the player.
 */
traceDownInFrontOfPlayer(id, Float:vTraceEndPos[3]) {
	//calculate position that's forward from the player
	gfOffsetX = gfOffsetUnitX * gForwardDist;
	gfOffsetY = gfOffsetUnitY * gForwardDist;
	
	//trace downwards from in front of the player
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, gvOrigin[0] + gfOffsetX, gvOrigin[1] + gfOffsetY, gvAbsMax[2]);
	xs_vec_set(vTraceTo, gvOrigin[0] + gfOffsetX, gvOrigin[1] + gfOffsetY, gvAbsMin[2] - 100.0);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
}

/**
 * Trace backwards towards the player to get what they're standing on.
 */
bool:traceBackwardsTowardsPlayer(id, const Float:vTraceStart[3], Float:vTraceEndPos[3], Float:vNormal[3]) {
	gfOffsetX = gfOffsetUnitX * -(gForwardDist + 10.0);
	gfOffsetY = gfOffsetUnitY * -(gForwardDist + 10.0);
	new Float:vTraceFrom[3];
	new Float:vTraceTo[3];
	xs_vec_set(vTraceFrom, vTraceStart[0], vTraceStart[1], gvAbsMin[2]);
	xs_vec_set(vTraceTo, vTraceStart[0] + gfOffsetX, vTraceStart[1] + gfOffsetY, gvAbsMin[2]);
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
bool:traceForwardsForDistance(id, const Float:vTraceFrom[3], const Float:vNormal[3], Float:vTraceEndPos[3]) {
	gfOffsetX = (vNormal[0] * 300.0);
	gfOffsetY = (vNormal[1] * 300.0);
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0] + gfOffsetX, vTraceFrom[1] + gfOffsetY, vTraceFrom[2]);
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
traceDownForDropHeight(id, const Float:vTraceFrom[3], Float:vTraceEndPos[3]) {
	new Float:vTraceTo[3];
	xs_vec_set(vTraceTo, vTraceFrom[0], vTraceFrom[1], vTraceFrom[2] - 80);
	new iTrace = 0;
	engfunc(EngFunc_TraceLine, vTraceFrom, vTraceTo, IGNORE_MONSTERS, id, iTrace);
	get_tr2(iTrace, TR_vecEndPos, vTraceEndPos);
}

/**
 * Do various traces to get and show the jump information.
 */
traceAndShowJumpDistance(id) {
	new iFlags = entity_get_int(id, EV_INT_flags);
	new bool:bUpdateBeam = false;
	new Float:vColor[3];

	//if player is alive and has feet on the ground
	if (is_user_alive(id) && iFlags & FL_ONGROUND) {
		//get player vectors of interest
		entity_get_vector(id, EV_VEC_origin, gvOrigin);
		entity_get_vector(id, EV_VEC_absmin, gvAbsMin);
		entity_get_vector(id, EV_VEC_absmax, gvAbsMax);
		entity_get_vector(id, EV_VEC_angles, gvAngles);
		gvAbsMin[2] += 0.9;	//needs doing, dunno why...
		
		//get direction player is facing as coordinate scalars
		gfOffsetUnitX = floatcos(gvAngles[1], degrees);
		gfOffsetUnitY = floatsin(gvAngles[1], degrees);
		
		//trace down in front of player, don't care if it hits anything or not
		new Float:vTraceEndPos[3];
		traceDownInFrontOfPlayer(id, vTraceEndPos);
		
		//get height difference between trace end point and players feet
		new Float:heightDelta = (gvAbsMin[2] - vTraceEndPos[2]);
		if (heightDelta > 8.0) {
			new Float:vPlayerEdge[3];
			new Float:vNormal[3];
			new bool:bHit = traceBackwardsTowardsPlayer(id, vTraceEndPos, vPlayerEdge, vNormal);
			if (bHit) {
				//trace forwards
				bHit = traceForwardsForDistance(id, vPlayerEdge, vNormal, vTraceEndPos);
				if (bHit) {
					new Float:fDistance = get_distance_f(vPlayerEdge, vTraceEndPos);
					new iDistance = floatround(fDistance, floatround_round);
					
					if (iDistance >= 100) {
						//update the beam position
						Beam_PointsInit(gDistanceBeam[id], vPlayerEdge, vTraceEndPos);
						
						//update digits
						gfOffsetX = (vNormal[0] * (fDistance / 2.0));
						gfOffsetY = (vNormal[1] * (fDistance / 2.0));
						new Float:vPosition[3]; 
						xs_vec_set(vPosition, vPlayerEdge[0] + gfOffsetX, vPlayerEdge[1] + gfOffsetY, vPlayerEdge[2]);
						set_distance_digits(gDistanceDigits[id], iDistance, vPosition, vNormal);
						
						//trace to get height of jump, don't care if it hits anything or not
						traceDownForDropHeight(id, vPlayerEdge, vTraceEndPos);
						new Float:fHeight = get_distance_f(vPlayerEdge, vTraceEndPos);
						if (fHeight < 70.0) {
							vColor = gvColorLj;
						} else {
							vColor = gvColorHj;
						}
						
//						console_print(id, "fHeight: %f", fHeight);
						
						bUpdateBeam = true;
					}
				}
			}
		}
	}

	//set the beam and digits visibility
	if (bUpdateBeam) {
		Beam_SetColor(gDistanceBeam[id], vColor);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 255.0);
			entity_set_vector(gDistanceDigits[id][i], EV_VEC_rendercolor, vColor);
		}
	} else {
		Beam_SetColor(gDistanceBeam[id], gvColor0);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 0.0);
		}
	}
}
