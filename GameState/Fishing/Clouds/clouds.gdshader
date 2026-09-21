shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded, shadows_disabled, ambient_light_disabled;

#include "res://GameState/Fishing/Clouds/hatch_shadow.gdshaderinc"   // also brings in smog_fbm/smog_billow/smog_hash

group_uniforms Clouds;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_scale : hint_range(0.0005, 0.05) = 0.006;     // frequency directly on world XZ - small numbers, world units are big
uniform float cloud_speed : hint_range(0.0, 20.0) = 2.5;          // world units/second of drift
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform vec3 cloud_top_color : source_color = vec3(0.46, 0.44, 0.36);
uniform vec3 cloud_under_color : source_color = vec3(0.09, 0.10, 0.09);
uniform float wind_direction_deg : hint_range(0.0, 360.0) = 30.0; // match your water's wind for the clouds to drift the same way

group_uniforms Fade;
uniform float fade_start : hint_range(0.0, 4000.0) = 500.0;   // camera-distance (world units) where the plane starts fading out
uniform float fade_end : hint_range(0.0, 8000.0) = 1100.0;    // fully invisible by here - hides the plane's edge in the haze

group_uniforms Sun;
// Pushed every frame by CloudLayer.gd from PollutedAtmosphere's own sun -
// do not rename these.
uniform vec3 sun_direction = vec3(0.3, -0.6, 0.3);   // direction the light TRAVELS in
uniform vec3 sun_color : source_color = vec3(0.92, 0.86, 0.64);
uniform float sun_energy : hint_range(0.0, 4.0) = 1.0;

// Same self-shadow -> hatch pipeline as new_sky.gdshader, applied to the
// cloud tops/undersides. Independent style/scale from the sky's smog so you
// can, say, keep the smog as soft relief but make the clouds cross-hatched.
group_uniforms Hatching;
uniform int hatch_style : hint_enum("Soft Relief", "Cross-Hatch", "Parallel Streaks", "Stipple") = 0;
uniform float hatch_scale : hint_range(0.5, 400.0) = 25.0;
uniform float hatch_strength : hint_range(0.0, 2.0) = 1.0;
uniform float hatch_angle_deg : hint_range(0.0, 180.0) = 45.0;
uniform float hatch_sharpness : hint_range(0.5, 8.0) = 3.0;

group_uniforms Biomes;
// Pushed by WaterBiomeSystem.gd, same world-space biome_data your water
// shader uses - do not rename these.
uniform vec4 biome_data[8];    // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_cloud[8];   // x = density mult, y = darken (0..1), z = extra turbulence (0..1), w = unused
uniform vec4 biome_look[8];    // x = tint strength (reused from the water biome's own tint_strength)
uniform vec4 biome_tint[8];    // rgb = tint color (reused from the water biome's own tint_color)

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wxz = v_world_pos.xz;

	// --- distance fade: hides the plane's finite edges in the haze instead
	// of showing a hard rectangle against the sky ---
	float cam_dist = length(wxz - CAMERA_POSITION_WORLD.xz);
	float edge_fade = 1.0 - smoothstep(fade_start, max(fade_end, fade_start + 1.0), cam_dist);
	if (edge_fade <= 0.001) {
		discard;
	}

	// --- blend biome influence at this world position, same soft-edged-circle
	// blend the water vertex shader uses ---
	vec4 bcloud = vec4(1.0, 0.0, 0.0, 0.0);   // density mult, darken, turbulence, unused
	float tint_strength = 0.0;
	vec3 tint_color = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= biome_count) {
			break;
		}
		vec2 center = biome_data[i].xy;
		float radius = biome_data[i].z;
		float blend = max(biome_data[i].w, 0.001);
		float dist = length(wxz - center);
		float w = 1.0 - smoothstep(radius, radius + blend, dist);
		bcloud = mix(bcloud, biome_cloud[i], w);
		tint_strength = mix(tint_strength, biome_look[i].x, w);
		tint_color = mix(tint_color, biome_tint[i].rgb, w);
	}

	// --- cloud shape: billowed fbm, wind-drifted, extra roiling noise added
	// under stormy biomes via bcloud.z (turbulence) ---
	float wind_rad = radians(wind_direction_deg);
	vec2 wind_dir = vec2(cos(wind_rad), sin(wind_rad));
	float t = TIME * cloud_speed;
	vec2 uv = wxz * cloud_scale + wind_dir * t * cloud_scale * 40.0;

	float n = smog_billow(uv);
	if (bcloud.z > 0.001) {
		vec2 turb_uv = wxz * cloud_scale * 2.6 + vec2(-t * 1.4, t * 0.9) * cloud_scale * 40.0;
		float turb_n = smog_billow(turb_uv);
		n = mix(n, max(n, turb_n), clamp(bcloud.z, 0.0, 1.0));
	}
	float n_lit = smog_billow(uv + sun_direction.xz * 0.12);

	float coverage = clamp(cloud_coverage * bcloud.x, 0.0, 1.0);
	float thr = 1.0 - coverage;
	float mask = smoothstep(thr - cloud_softness, thr + cloud_softness, n);
	float alpha = clamp(mask * cloud_density, 0.0, 1.0);

	// --- shading: lit tops vs sooty undersides, using the hand-fed sun,
	// rendered through the same hatch pipeline as the sky's smog ---
	float relief = hatch_relief_from_samples(n, n_lit, hatch_sharpness);
	float shaded = apply_hatch(uv, relief, hatch_style, hatch_scale, hatch_strength, hatch_angle_deg);
	vec3 col = mix(cloud_under_color, cloud_top_color, shaded);
	col *= mix(vec3(1.0), sun_color, 0.5) * mix(0.6, 1.0, sun_energy * 0.4 + 0.3);

	// darken toward storm-biome soot, and tint toward the biome's water colour
	col = mix(col, col * 0.35, clamp(bcloud.y, 0.0, 1.0));
	col = mix(col, tint_color, clamp(tint_strength, 0.0, 1.0) * 0.5);

	ALBEDO = col;
	ALPHA = alpha * edge_fade;
}
