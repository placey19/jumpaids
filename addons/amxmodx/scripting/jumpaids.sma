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
new giTrace = 0;
new giDistance;
new Float:gfDistance;
new Float:gfFraction;
new Float:gfOffsetUnitX;
new Float:gfOffsetUnitY;
new Float:gfOffsetX;
new Float:gfOffsetY;
new Float:gvOrigin[3];
new Float:gvAbsMin[3];
new Float:gvAbsMax[3];
new Float:gvAngles[3];
new Float:gvTraceStart[3];
new Float:gvTraceEnd[3];
new Float:gvTraceHit[3];
new Float:gvPlayerEdge[3];
new Float:gvNormal[3];

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

public set_distance_digits(const digits[3], const distance, const Float:vOrigin[3], Float:vNormal[3]) {
	new const Float:fDigitGapSize = 10.0;
	new Float:vPos[3];
	
	//create string from distance value
	new szDistance[4];
	format(szDistance, 3, "%d", distance);
	
	console_print(0, "vNormal: %f, %f, %f (%f)", vNormal[0], vNormal[1], vNormal[2], xs_vec_len(vNormal));
	
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

public setvec(Float:vec[3], Float:x, Float:y, Float:z) {
	vec[0] = x;
	vec[1] = y;
	vec[2] = z;
}

/**
 * Get the edge of the block that the player is standing on.
 */
//getEdgeOfPlayerBlock() {
//}

/**
 * Main method to call to trace jump and show beam and jump distance.
 */
public traceAndShowJumpDistance(id) {
	new flags = entity_get_int(id, EV_INT_flags);
	new bool:updateBeam = false;
	new Float:color[3];

	//if player is alive and has feet on the ground
	if (is_user_alive(id) && flags & FL_ONGROUND) {
		//get player vectors of interest
		entity_get_vector(id, EV_VEC_origin, gvOrigin);
		entity_get_vector(id, EV_VEC_absmin, gvAbsMin);
		entity_get_vector(id, EV_VEC_absmax, gvAbsMax);
		entity_get_vector(id, EV_VEC_angles, gvAngles);
		gvAbsMin[2] += 0.9;	//needs doing, dunno why...
		
		//calculate forward position
		gfOffsetUnitX = floatcos(gvAngles[1], degrees);
		gfOffsetUnitY = floatsin(gvAngles[1], degrees);
		gfOffsetX = gfOffsetUnitX * gForwardDist;
		gfOffsetY = gfOffsetUnitY * gForwardDist;
		
		//setup the trace start and end vectors
		setvec(gvTraceStart, gvOrigin[0] + gfOffsetX, gvOrigin[1] + gfOffsetY, gvAbsMax[2]);
		setvec(gvTraceEnd, gvOrigin[0] + gfOffsetX, gvOrigin[1] + gfOffsetY, gvAbsMin[2] - 100.0);
		
		//do the trace
		engfunc(EngFunc_TraceLine, gvTraceStart, gvTraceEnd, IGNORE_MONSTERS, id, giTrace);
		  
		//get the trace hit vector
		get_tr2(giTrace, TR_vecEndPos, gvTraceHit);
		
		//get difference between trace hit point and players feet
		new Float:heightDelta = (gvAbsMin[2] - gvTraceHit[2]);
		if (heightDelta > 2.0) {
			//trace backwards towards player to hit what they're standing on
			gfOffsetX = gfOffsetUnitX * -(gForwardDist + 10.0);
			gfOffsetY = gfOffsetUnitY * -(gForwardDist + 10.0);
			setvec(gvTraceStart, gvTraceHit[0], gvTraceHit[1], gvAbsMin[2]);
			setvec(gvTraceEnd, gvTraceHit[0] + gfOffsetX, gvTraceHit[1] + gfOffsetY, gvAbsMin[2]);
			engfunc(EngFunc_TraceLine, gvTraceStart, gvTraceEnd, IGNORE_MONSTERS, id, giTrace);
			
			get_tr2(giTrace, TR_flFraction, gfFraction);
			if (gfFraction != 1.0) {
				get_tr2(giTrace, TR_vecEndPos, gvPlayerEdge);
				get_tr2(giTrace, TR_vecPlaneNormal, gvNormal);
				
				//ensure the normal is perpendicular to the ground
				if (gvNormal[2] != 0.0) {
					gvNormal[2] = 0.0;
					xs_vec_normalize(gvNormal, gvNormal);
				}
				
				//trace forwards 
				gfOffsetX = (gvNormal[0] * 300.0);
				gfOffsetY = (gvNormal[1] * 300.0); 
				setvec(gvTraceStart, gvPlayerEdge[0], gvPlayerEdge[1], gvPlayerEdge[2]);
				setvec(gvTraceEnd, gvPlayerEdge[0] + gfOffsetX, gvPlayerEdge[1] + gfOffsetY, gvPlayerEdge[2]);
				engfunc(EngFunc_TraceLine, gvTraceStart, gvTraceEnd, IGNORE_MONSTERS, id, giTrace);
				
				get_tr2(giTrace, TR_flFraction, gfFraction);
				if (gfFraction != 1.0) {
					get_tr2(giTrace, TR_vecEndPos, gvTraceHit);
					gfDistance = get_distance_f(gvPlayerEdge, gvTraceHit);
					giDistance = floatround(gfDistance, floatround_round);
					
					if (giDistance >= 150) {
						//update the beam
						Beam_PointsInit(gDistanceBeam[id], gvPlayerEdge, gvTraceHit);
						
						//update digits
						gfOffsetX = (gvNormal[0] * (gfDistance / 2.0));
						gfOffsetY = (gvNormal[1] * (gfDistance / 2.0));
						new Float:vTemp[3]; 
						setvec(vTemp, gvPlayerEdge[0] + gfOffsetX, gvPlayerEdge[1] + gfOffsetY, gvPlayerEdge[2]);
						set_distance_digits(gDistanceDigits[id], giDistance, vTemp, gvNormal);
						
						//trace downwards to get height - whether its a LJ or HJ
						setvec(gvTraceStart, gvPlayerEdge[0], gvPlayerEdge[1], gvPlayerEdge[2]);
						setvec(gvTraceEnd, gvPlayerEdge[0], gvPlayerEdge[1], gvPlayerEdge[2] + 1 - 80);
						engfunc(EngFunc_TraceLine, gvTraceStart, gvTraceEnd, IGNORE_MONSTERS, id, giTrace);
						get_tr2(giTrace, TR_vecEndPos, gvTraceHit);
						gfDistance = get_distance_f(gvPlayerEdge, gvTraceHit);
						if (gfDistance < 70.0) {
							color = gvColorLj;
						} else {
							color = gvColorHj;
						}
						
						updateBeam = true;
					}
				}
			}
		}
	}

	//set the beam and digits visibility
	if (updateBeam) {
		Beam_SetColor(gDistanceBeam[id], color);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 255.0);
			entity_set_vector(gDistanceDigits[id][i], EV_VEC_rendercolor, color);
		}
	} else {
		Beam_SetColor(gDistanceBeam[id], gvColor0);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 0.0);
		}
	}
}
