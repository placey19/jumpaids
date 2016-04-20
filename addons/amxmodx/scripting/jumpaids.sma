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
new const Float:vColor0[3] = { 0.0, 0.0, 0.0 };
new const Float:vColorLj[3] = { 0.0, 255.0, 0.0 };
new const Float:vColorHj[3] = { 200.0, 100.0, 0.0 };

new Float:vTemp[3];
new gMaxPlayers;
new gDistanceBeam[33];
new gDistanceDigits[33][3];

public plugin_precache() {
	precache_model(gszDotSprite);
	precache_model(gszDigits);
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_cfg() {
	gMaxPlayers = get_maxplayers();

	for (new id = 1; id <= gMaxPlayers; id++) {
		gDistanceBeam[id] = Beam_Create(gszDotSprite, 2.0);
		
		//create 3 new entities to use for the distance digits
		for (new i = 0; i < 3; ++i) {
			new ent = create_entity(gszInfoTarget);
			if (is_valid_ent(ent)) {
				entity_set_string(ent, EV_SZ_classname, gszDigitClassname);
				entity_set_model(ent, gszDigits);
				entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);
				entity_set_float(ent, EV_FL_renderamt, 0.0);
				entity_set_vector(ent, EV_VEC_rendercolor, vColor0);
				entity_set_float(ent, EV_FL_scale, 0.5);
			}
			gDistanceDigits[id][i] = ent;
		}
	}
}

public client_PreThink(id) {
	traceAndShowJumpDistance(id);
}

public set_distance_digits(const digits[3], const distance, const Float:vOrigin[3], const Float:vNormal[3]) {
	new const Float:fDigitGapSize = 10.0;
	new Float:vPos[3];
	
	//create string from distance value
	new szDistance[4];
	format(szDistance, 3, "%d", distance);
	
	//get the angles the digits will be at based off the given normal
	new Float:vAngles[3];
	vector_to_angle(vNormal, vAngles);
	
	for (new i = 0; i < 3; ++i) {
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

public traceAndShowJumpDistance(id) {
	new flags = entity_get_int(id, EV_INT_flags);
	new bool:updatedBeam = false;
	new Float:color[3];

	//if player is alive and has feet on the ground
	if (is_user_alive(id) && flags & FL_ONGROUND) {
		//get player vectors of interest
		new Float:pOrigin[3];
		new Float:pAbsMin[3];
		new Float:pAbsMax[3];
		new Float:pAngles[3];
		entity_get_vector(id, EV_VEC_origin, pOrigin);
		entity_get_vector(id, EV_VEC_absmin, pAbsMin);
		entity_get_vector(id, EV_VEC_absmax, pAbsMax);
		entity_get_vector(id, EV_VEC_angles, pAngles);
		
		//calculate forward position
		new Float:offsetUnitX = floatcos(pAngles[1], degrees);
		new Float:offsetUnitY = floatsin(pAngles[1], degrees);
		new Float:forwardDist = 100.0;
		new Float:offsetX = offsetUnitX * forwardDist;
		new Float:offsetY = offsetUnitY * forwardDist;
		
		//setup the trace start and end vectors
		new Float:vTraceStart[3];
		new Float:vTraceEnd[3];
		setvec(vTraceStart, pOrigin[0] + offsetX, pOrigin[1] + offsetY, pAbsMax[2]);
		setvec(vTraceEnd, pOrigin[0] + offsetX, pOrigin[1] + offsetY, pAbsMin[2] - 100.0);
		
		//do the trace
		new trace = 0;
		engfunc(EngFunc_TraceLine, vTraceStart, vTraceEnd, IGNORE_MONSTERS, id, trace);
		  
		//get the trace hit vector
		new Float:vTraceHit[3];
		get_tr2(trace, TR_vecEndPos, vTraceHit);
		
		//get difference between trace hit point and players feet. Dunno why the +1
		new Float:heightDelta = (pAbsMin[2] - vTraceHit[2] + 1.0);
		if (heightDelta > 2.0) {
			//trace backwards towards player to hit what they're standing on
			offsetX = offsetUnitX * -(forwardDist + 10.0);
			offsetY = offsetUnitY * -(forwardDist + 10.0);
			vTemp[2] = pAbsMin[2];
			setvec(vTraceStart, vTraceHit[0], vTraceHit[1], vTemp[2]);
			setvec(vTraceEnd, vTraceHit[0] + offsetX, vTraceHit[1] + offsetY, vTemp[2]);
			engfunc(EngFunc_TraceLine, vTraceStart, vTraceEnd, IGNORE_MONSTERS, id, trace);
			
			new Float:fraction;
			get_tr2(trace, TR_flFraction, fraction);
			if (fraction != 1.0) {
				new Float:vPlayerEdge[3];
				new Float:vNormal[3];
				get_tr2(trace, TR_vecEndPos, vPlayerEdge);
				get_tr2(trace, TR_vecPlaneNormal, vNormal);
				
				//trace forwards 
				offsetX = (vNormal[0] * 300.0);
				offsetY = (vNormal[1] * 300.0); 
				setvec(vTraceStart, vPlayerEdge[0], vPlayerEdge[1], vPlayerEdge[2]);
				setvec(vTraceEnd, vPlayerEdge[0] + offsetX, vPlayerEdge[1] + offsetY, vPlayerEdge[2]);
				engfunc(EngFunc_TraceLine, vTraceStart, vTraceEnd, IGNORE_MONSTERS, id, trace);
				
				get_tr2(trace, TR_flFraction, fraction);
				if (fraction != 1.0) {
					get_tr2(trace, TR_vecEndPos, vTraceHit);
					new Float:fDistance = get_distance_f(vPlayerEdge, vTraceHit);
					new iDistance = floatround(fDistance, floatround_round);
					
					if (iDistance >= 150) {
						//update the beam
						Beam_PointsInit(gDistanceBeam[id], vPlayerEdge, vTraceHit);
						
						//update digits
						offsetX = (vNormal[0] * (fDistance / 2.0));
						offsetY = (vNormal[1] * (fDistance / 2.0));
						setvec(vTemp, vPlayerEdge[0] + offsetX, vPlayerEdge[1] + offsetY, vPlayerEdge[2]);
						set_distance_digits(gDistanceDigits[id], iDistance, vTemp, vNormal);
						
						//trace downwards to get height - whether its a LJ or HJ
						setvec(vTraceStart, vPlayerEdge[0], vPlayerEdge[1], vPlayerEdge[2]);
						setvec(vTraceEnd, vPlayerEdge[0], vPlayerEdge[1], vPlayerEdge[2] + 1 - 80);
						engfunc(EngFunc_TraceLine, vTraceStart, vTraceEnd, IGNORE_MONSTERS, id, trace);
						get_tr2(trace, TR_vecEndPos, vTraceHit);
						fDistance = get_distance_f(vPlayerEdge, vTraceHit);
						if (fDistance < 70.0) {
							color = vColorLj;
						} else {
							color = vColorHj;
						}
						updatedBeam = true;
						
						//temp stuff
						console_print(id, "distance: %f", fDistance);
					}
				}
			}
		}
	}

	//set the beam and digits visibility
	if (updatedBeam) {
		Beam_SetColor(gDistanceBeam[id], color);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 255.0);
			entity_set_vector(gDistanceDigits[id][i], EV_VEC_rendercolor, color);
		}
	} else {
		Beam_SetColor(gDistanceBeam[id], vColor0);
		for (new i = 0; i < 3; ++i) {
			entity_set_float(gDistanceDigits[id][i], EV_FL_renderamt, 0.0);
		}
	}
}
