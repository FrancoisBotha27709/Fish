shader_type sky;

#include "res://GameState/Fishing/Clouds/hatch_shadow.gdshaderinc"   // also brings in smog_fbm/smog_billow/smog_hash

group_uniforms Colors;
uniform vec3 zenith_color : source_color = vec3(0.05, 0.06, 0.055);      // dark neutral grey, whisper of green
uniform vec3 horizon_color : source_color = vec3(0.42, 0.40, 0.33);       // grey-brown haze, hint of green
uniform vec3 ground_color : source_color = vec3(0.16, 0.15, 0.12);        // below the horizon (only seen in reflections/ambient)
uniform vec3 smog_light_color : source_color = vec3(0.55, 0.52, 0.42);    // smog catching the sun - warm grey-brown
uniform vec3 smog_dark_color : source_color = vec3(0.11, 0.12, 0.10);    // soot-heavy undersides, not near-black

group_uniforms Smog;
uniform float smog_coverage : hint_range(0.0, 1.0) = 0.75;
uniform float smog_density : hint_range(0.0, 3.0) = 1.1;
uniform float smog_scale : hint_range(0.2, 6.0) = 1.4;
uniform float smog_speed : hint_range(0.0, 0.05) = 0.006;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.45;                // thick band of haze at the horizon

// The old self-shadow trick (offset-sample the smog noise toward the sun,
// diff the two) is now hatch_relief()/apply_hatch() from hatch_shadow.gdshaderinc.
// hatch_style picks how that shadow value gets rendered - the original smooth
// look, or actual pen-and-ink hatch marks.
group_uniforms Hatching;
uniform int hatch_style : hint_enum("Soft Relief", "Cross-Hatch", "Parallel Streaks", "Stipple") = 0;
uniform float hatch_scale : hint_range(1.0, 400.0) = 40.0;        // line/dot spacing
uniform float hatch_strength : hint_range(0.0, 2.0) = 1.0;        // how readily shadow turns into visible marks
uniform float hatch_angle_deg : hint_range(0.0, 180.0) = 45.0;
uniform float hatch_offset : hint_range(0.01, 0.5) = 0.12;        // self-shadow sample offset toward the sun
uniform float hatch_sharpness : hint_range(0.5, 8.0) = 4.0;       // contrast of the relief before hatching

group_uniforms Sun;
uniform float sun_glow : hint_range(0.0, 4.0) = 0.9;

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, 0.0, 1.0);
	vec2 sun_xz = LIGHT0_DIRECTION.xz;

	// --- base gradient: grey-brown haze low, dark neutral grey overhead ---
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, dir.y));

	// --- smog: closer, faster, ground-hugging drift. Two layers projected onto
	// a flat ceiling; the projection compresses detail toward the horizon, which
	// is what gives the "endless smoggy distance" look. ---
	{
		float t = TIME * smog_speed;
		vec2 uv = dir.xz / (h + 0.22);
		vec2 drift = vec2(t, t * 0.6);
		vec2 smog_uv = uv * smog_scale + drift;

		float n1 = smog_fbm(smog_uv);
		float n2 = smog_fbm(uv * smog_scale * 2.3 + vec2(-t * 1.7, t * 1.1) + 17.0);
		float n = n1 * 0.7 + n2 * 0.3;

		float thr = 1.0 - smog_coverage;
		float cloud = smoothstep(thr - 0.05, thr + 0.35, n);
		float alpha = clamp(cloud * smog_density, 0.0, 1.0);

		float relief = hatch_relief(smog_uv, sun_xz, hatch_offset, hatch_sharpness);
		float sun_near = pow(max(dot(dir, LIGHT0_DIRECTION), 0.0), 3.0);
		float lit = clamp(relief * 0.8 + sun_near * 0.5 - 0.1, 0.0, 1.0);
		float shaded = apply_hatch(smog_uv, lit, hatch_style, hatch_scale, hatch_strength, hatch_angle_deg);

		vec3 smog_col = mix(smog_dark_color, smog_light_color, shaded);
		smog_col = mix(smog_col, horizon_color, (1.0 - h) * 0.5);          // smog looks paler and hazier in the distance

		col = mix(col, smog_col, alpha);
	}

	// --- thick haze band along the horizon; matches the fog colour so water melts into it ---
	col = mix(col, horizon_color, pow(1.0 - h, 3.0) * haze_strength);

	// --- sun: a dirty glow, with the disc mostly smothered by smog ---
	if (LIGHT0_ENABLED) {
		float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		vec3 sun_c = mix(vec3(1.0, 0.9, 0.45), LIGHT0_COLOR, 0.3) * LIGHT0_ENERGY;
		float broad = pow(sd, 8.0) * 0.35 + pow(sd, 64.0) * 0.8;
		float disc = smoothstep(0.9995, 0.9999, sd) * 4.0;
		col += sun_c * sun_glow * (broad + disc);
	}

	COLOR = col;
}
