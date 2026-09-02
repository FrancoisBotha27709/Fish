shader_type sky;

group_uniforms cloud_data;
uniform sampler2D sky_texture;
uniform float power = 0.2;
uniform float scale_a = 0.5;
uniform float scale_b = 0.3;

group_uniforms speed;
uniform float speed = 0.2;
uniform vec2 speed_a = vec2(0.1);
uniform vec2 speed_b = vec2(0.1);

group_uniforms toxic_clouds;
uniform float density : hint_range(0.0, 2.0) = 0.9;
uniform float grayness : hint_range(0.0, 1.0) = 0.2;
uniform float cloud_light = 1.0;
uniform float cloud_distortion = 0.2;
uniform float cloud_edge_softness : hint_range(0.001, 0.2, 0.001) = 0.02;
uniform int cloud_shade_steps : hint_range(2, 3, 1) = 2;
uniform vec3 cloud_color_light : source_color = vec3(0.55, 0.58, 0.42);
uniform vec3 cloud_color_dark : source_color = vec3(0.18, 0.2, 0.14);

group_uniforms cloud_depth;
// fake-3D "bump" shading built from the noise gradient — this is what breaks up
// dense/flat areas into lumps, ridges, and pockets of shadow.
uniform float bump_sample_offset : hint_range(0.0005, 0.02, 0.0005) = 0.004; // distance between gradient samples, smaller = finer bumps
uniform float bump_strength : hint_range(0.0, 10.0, 0.1) = 3.0; // how tall the fake bumps read, higher = more relief
uniform int bump_light_steps : hint_range(1, 4, 1) = 2; // 1 = smooth lighting, 2-4 = toon-banded lighting on the bumps
uniform vec3 bump_shadow_tint : source_color = vec3(0.35, 0.35, 0.4); // multiplies onto color where the fake normal faces away from the light
uniform vec3 bump_highlight_tint : source_color = vec3(1.3, 1.25, 1.1); // multiplies onto color where the fake normal faces the light (can exceed 1.0 to punch highlights)
uniform float bump_ao_strength : hint_range(0.0, 1.0, 0.01) = 0.4; // darkens the thickest/densest parts of the field, like ambient occlusion in the folds

group_uniforms cloud_underside;
uniform vec3 cloud_underside_color : source_color = vec3(0.06, 0.07, 0.05);
uniform float cloud_loom : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float cloud_underside_strength : hint_range(0.0, 1.0, 0.01) = 0.85;

group_uniforms cloud_grime;
uniform float cloud_grime_scale : hint_range(1.0, 20.0, 0.5) = 6.0;
uniform vec2 cloud_grime_speed = vec2(0.02, -0.015);
uniform float cloud_grime_cutoff : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float cloud_grime_strength : hint_range(0.0, 1.0, 0.01) = 0.4;

group_uniforms smog;
uniform vec3 smog_color : source_color = vec3(0.35, 0.4, 0.22);
uniform float smog_height : hint_range(0.0, 0.5, 0.01) = 0.15;
uniform float smog_density : hint_range(0.0, 2.0, 0.05) = 1.0;

group_uniforms sky_color;
uniform vec3 sky_color_a0 : source_color = vec3(0.35, 0.4, 0.28);
uniform vec3 sky_color_b0 : source_color = vec3(0.15, 0.2, 0.15);
uniform vec3 sky_color_a1 : source_color = vec3(0.1, 0.12, 0.09);
uniform vec3 sky_color_b1 : source_color = vec3(0.03, 0.04, 0.03);

group_uniforms ground_colors;
uniform vec3 ground_color_a0 : source_color = vec3(0.2, 0.18, 0.1);
uniform vec3 ground_color_b0 : source_color = vec3(0.08, 0.08, 0.05);
uniform vec3 ground_color_a1 : source_color = vec3(0.05, 0.05, 0.04);
uniform vec3 ground_color_b1 : source_color = vec3(0.02, 0.02, 0.02);

group_uniforms sun_data;
uniform vec3 sun_color_a : source_color = vec3(0.9, 0.75, 0.3);
uniform vec3 sun_color_b : source_color = vec3(0.8, 0.35, 0.15);
uniform float sun_size = 0.995;
uniform float sun_softness = 0.002;
uniform vec2 sunset_range = vec2(-0.1, 0.3);

float to_grayscale(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 do_ceil(vec3 eye, vec3 sun) {
	vec3 mix_0 = mix(sky_color_a0, sky_color_b0, eye.y);
	vec3 mix_1 = mix(sky_color_a1, sky_color_b1, eye.y);
	return mix(mix_1, mix_0, smoothstep(sunset_range.x, sunset_range.y, sun.y));
}

vec3 do_floor(vec3 eye, vec3 sun) {
	vec3 mix_0 = mix(ground_color_a0, ground_color_b0, -eye.y);
	vec3 mix_1 = mix(ground_color_a1, ground_color_b1, -eye.y);
	return mix(mix_1, mix_0, smoothstep(sunset_range.x, sunset_range.y, sun.y));
}

// Cheap "height" read of the cloud noise at a given uv, used both for the main
// mask and for building a fake normal via finite differences.
float sample_cloud_height(vec2 uv_a) {
	vec2 uv_b = (uv_a - TIME * speed_a * speed) * (scale_b / max(scale_a, 0.0001)) + TIME * speed_b * speed;
	uv_b += texture(sky_texture, uv_a).rg * cloud_distortion;
	float a = texture(sky_texture, uv_a).r;
	float b = texture(sky_texture, uv_b).r;
	return a + b;
}

void sky() {
	// LIGHT0_DIRECTION should already be unit length, but if the light (or
	// any parent node above it) ever picks up a non-1 scale, Godot can pass
	// a longer vector through. dot(EYEDIR, LIGHT0_DIRECTION) then stops being
	// a clean cosine of the angle between them — it becomes
	// magnitude * cos(angle) — which can stay above the sun_size threshold
	// across a huge range of angles instead of just near the light itself,
	// showing up as a hard-edged wedge across a big chunk of the sky rather
	// than a small disc. Force it to unit length so the sun math is always
	// a true angular comparison regardless of upstream transform scale.
	vec3 light_dir = normalize(LIGHT0_DIRECTION);

	float fade = pow(abs(EYEDIR.y), power);

	// EYEDIR.xz / EYEDIR.y is a horizon-plane projection: as EYEDIR.y -> 0
	// (i.e. the view direction gets close to the horizon, which happens
	// constantly during normal play) this divide blows up toward +/-inf and
	// can hand texture() a NaN/inf uv. NaN then survives the "* fade" below
	// (NaN * 0 is still NaN, not 0) and poisons cloud_field, cloud_mask and
	// eventually COLOR -- which is what shows up as a solid, wrong-colored
	// blob smeared across a big chunk of the sky. Clamping the denominator's
	// magnitude keeps the projection finite without changing it anywhere
	// away from the horizon.
	float eye_y_sign = EYEDIR.y >= 0.0 ? 1.0 : -1.0;
	float eye_y_safe = eye_y_sign * max(abs(EYEDIR.y), 0.05);
	vec2 uv_a = (EYEDIR.xz / eye_y_safe) * scale_a + TIME * speed_a * speed;

	float cloud_field = sample_cloud_height(uv_a) * fade;
	float cloud_mask = smoothstep(density - cloud_edge_softness, density + cloud_edge_softness, cloud_field);

	// flat, hard-stepped base tone
	float steps = float(cloud_shade_steps);
	float banded = floor(cloud_field * steps) / steps;
	vec3 flat_color = mix(cloud_color_dark, cloud_color_light, step(1.0 / steps, banded));

	// --- fake 3D bump shading ---
	// Sample the height field slightly offset in x and y. The difference tells us
	// which way the "surface" is tilting at this point, same idea as a normal map,
	// but derived on the fly from the same noise instead of needing real geometry.
	float h_r = sample_cloud_height(uv_a + vec2(bump_sample_offset, 0.0)) * fade;
	float h_u = sample_cloud_height(uv_a + vec2(0.0, bump_sample_offset)) * fade;
	vec3 fake_normal = normalize(vec3((cloud_field - h_r) * bump_strength, (cloud_field - h_u) * bump_strength, 1.0));

	// light the fake surface with the same directional light used for the sun/sky
	float bump_light = dot(fake_normal, normalize(vec3(LIGHT0_DIRECTION.x, LIGHT0_DIRECTION.z, LIGHT0_DIRECTION.y))) * 0.5 + 0.5;
	if (bump_light_steps > 1) {
		float bsteps = float(bump_light_steps);
		bump_light = floor(bump_light * bsteps) / max(bsteps - 1.0, 1.0);
		bump_light = clamp(bump_light, 0.0, 1.0);
	}
	vec3 bump_tint = mix(bump_shadow_tint, bump_highlight_tint, bump_light);
	flat_color *= bump_tint;

	// ambient occlusion: the densest/thickest parts of the field (deep in the folds)
	// read darker, regardless of light direction — sells weight/thickness
	float ao = smoothstep(density, density + 0.6, cloud_field) * bump_ao_strength;
	flat_color = mix(flat_color, flat_color * 0.35, ao);

	// --- dirty underside ---
	float underside_amount = (1.0 - smoothstep(0.0, cloud_loom, clamp(EYEDIR.y, 0.0, 1.0))) * cloud_underside_strength;
	flat_color = mix(flat_color, cloud_underside_color, underside_amount * cloud_mask);

	// --- grime/stain overlay ---
	vec2 grime_uv = uv_a * (cloud_grime_scale / max(scale_a, 0.001)) + TIME * cloud_grime_speed;
	float grime = texture(sky_texture, grime_uv).g;
	float grime_mask = smoothstep(cloud_grime_cutoff - 0.05, cloud_grime_cutoff + 0.05, grime) * cloud_mask;
	flat_color = mix(flat_color, cloud_underside_color, grime_mask * cloud_grime_strength);

	vec3 sky_back = EYEDIR.y > 0.0 ? do_ceil(EYEDIR, light_dir) : vec3(0.0);
	vec3 sky_with_clouds = mix(sky_back, flat_color, cloud_mask * clamp(cloud_light, 0.0, 1.0));

	float smog_factor = EYEDIR.y > 0.0
		? clamp(1.0 - (EYEDIR.y / max(smog_height, 0.001)), 0.0, 1.0) * smog_density
		: 0.0;
	sky_with_clouds = mix(sky_with_clouds, smog_color, smog_factor);

	// sun_size/sun_softness define a smoothstep(edge0, edge1, x); if edge1 ever
	// equals edge0 (softness pushed to 0 from the inspector) that's undefined
	// behavior in GLSL and can rasterize as a huge solid disc instead of a
	// tiny point. max(..., 0.0005) keeps the two edges from ever colliding.
	float sun_dot = max(0.0, dot(EYEDIR, light_dir));
	float sun = smoothstep(sun_size, sun_size + max(sun_softness, 0.0005), sun_dot);

	COLOR = vec3(0.0);
	COLOR = EYEDIR.y > 0.0 ? mix(sky_with_clouds, vec3(to_grayscale(sky_with_clouds)), grayness) : COLOR;
	COLOR += sun * mix(sun_color_b, sun_color_a, smoothstep(sunset_range.x, sunset_range.y, light_dir.y));

	COLOR = EYEDIR.y < 0.0 ? do_floor(EYEDIR, light_dir) : COLOR;

	// Last-resort safety net: if anything upstream still produced NaN/inf
	// (bad texture import, extreme uniform values, etc.) don't let it paint
	// a giant blown-out patch — fall back to black rather than garbage.
	if (isnan(COLOR.x) || isnan(COLOR.y) || isnan(COLOR.z)) {
		COLOR = vec3(0.0);
	}
	COLOR = clamp(COLOR, vec3(0.0), vec3(4.0));
}
