shader_type spatial;
// Stylized flat-water version.
// - No specular, no fresnel/rim, no reflections, no detail-normal glitter, no caustics, no oil-film iridescence.
// - Colour comes from a shallow -> deep gradient driven by water depth (optionally banded, toon style).
// - Lighting is plain lambert with the surface normal flattened toward "up", so the water reads as a flat colour.
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords, diffuse_lambert, specular_disabled;

group_uniforms Waves;
uniform float swell_amplitude : hint_range(0.0, 12.0) = 3.2;
uniform float swell_wavelength_scale : hint_range(0.2, 4.0) = 1.0;
uniform float chop_amplitude : hint_range(0.0, 2.0) = 0.35;
uniform float wave_speed     : hint_range(0.0, 3.0) = 1.0;
uniform float wave_choppiness: hint_range(0.0, 1.2) = 0.9;
uniform float wind_direction_deg : hint_range(0.0, 360.0) = 30.0;
uniform float wave_direction_jitter : hint_range(0.0, 60.0) = 20.0;
uniform float chop_patchiness : hint_range(0.0, 1.0) = 0.5;

group_uniforms Large_Scale_Variation;
uniform float domain_warp_amount : hint_range(0.0, 100.0) = 35.0;
uniform float domain_warp_scale : hint_range(0.0005, 0.05) = 0.004;
uniform float domain_warp_speed : hint_range(0.0, 0.2) = 0.02;

group_uniforms Scale;
uniform float meters_per_unit : hint_range(0.001, 100.0) = 1.0;
uniform float mesh_vertex_spacing : hint_range(0.05, 20.0) = 1.25;

group_uniforms Water_Colour;
// Colour in very shallow water and colour in deep water. The gradient between them follows water depth.
uniform vec4 color_shallow : source_color = vec4(0.25, 0.60, 0.52, 1.0);
uniform vec4 color_deep : source_color = vec4(0.04, 0.22, 0.24, 1.0);
// Metres of water until the colour is ~63% of the way from shallow to deep.
uniform float depth_fade_distance : hint_range(0.1, 60.0) = 3.0;
// 0 = smooth gradient. 2-6 = hard toon bands of colour.
uniform int depth_bands : hint_range(0, 8) = 0;
// Slightly lighter colour on wave crests (does nothing on perfectly flat water).
uniform vec4 color_crest : source_color = vec4(0.32, 0.72, 0.62, 1.0);
uniform float crest_amount : hint_range(0.0, 1.0) = 0.25;
// Big slow patches of a second tint so open water isn't one flat colour.
uniform vec4 color_variation_tint : source_color = vec4(0.10, 0.20, 0.05, 1.0);
uniform float color_variation_scale : hint_range(0.0005, 0.05) = 0.005;
uniform float color_variation_speed : hint_range(0.0, 0.05) = 0.003;
uniform float color_variation_strength : hint_range(0.0, 1.0) = 0.25;

group_uniforms See_Through;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float see_through : hint_range(0.0, 1.0) = 0.85;          // how visible the sea floor / hulls are at the waterline
uniform float clarity_distance : hint_range(0.1, 30.0) = 2.5;     // metres of water until things underneath fade out
uniform float see_through_tint : hint_range(0.0, 1.0) = 0.35;     // how much the water hue tints what you see through it

group_uniforms Shading;
// 0 = light follows the wave slopes. 1 = perfectly flat shading (same colour everywhere).
uniform float normal_flatten : hint_range(0.0, 1.0) = 0.75;

group_uniforms Pollution;
uniform float pollution_amount : hint_range(0.0, 1.0) = 0.35;     // global; biome_look.w is added on top
uniform float pollution_murk : hint_range(0.0, 8.0) = 3.0;        // how much faster the water turns opaque/deep when polluted
uniform float slick_scale : hint_range(0.0005, 0.1) = 0.02;
uniform vec4 slick_color : source_color = vec4(0.10, 0.09, 0.14, 1.0);   // flat dark patches (oil), no iridescence
uniform float slick_strength : hint_range(0.0, 1.0) = 0.7;
uniform vec4 scum_color : source_color = vec4(0.22, 0.24, 0.07, 1.0);
uniform float scum_scale : hint_range(0.0005, 0.1) = 0.02;
uniform float scum_strength : hint_range(0.0, 1.0) = 0.6;

group_uniforms Foam;
uniform vec4 color_foam : source_color = vec4(0.88, 0.90, 0.82, 1.0);
uniform float foam_jacobian_threshold : hint_range(-1.0, 1.5) = 0.75;
uniform float foam_edge_softness : hint_range(0.01, 1.0) = 0.55;
uniform float foam_threshold_jitter : hint_range(0.0, 1.0) = 0.5;
uniform float foam_noise_scale : hint_range(0.01, 1.0) = 0.15;
uniform float foam_scroll_speed : hint_range(0.0, 2.0) = 0.2;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.65;
uniform float foam_crispness : hint_range(0.0, 1.0) = 0.85;       // 0 = soft/misty, 1 = hard cel-shaded edge
uniform bool use_custom_foam_texture = false;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform float foam_uv_scale : hint_range(0.05, 12.0) = 2.0;
uniform float foam_uv_scale_2 : hint_range(0.05, 12.0) = 2.7;
uniform float foam_warp_amount : hint_range(0.0, 1.0) = 0.5;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.12;
uniform float foam_crest_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float foam_crest_softness : hint_range(0.01, 1.0) = 0.3;

group_uniforms Shore_Foam;
uniform bool enable_shore_foam = true;
uniform float shore_foam_distance : hint_range(0.0, 12.0) = 0.8;  // vertical metres of water depth the foam line covers
uniform float shore_band_speed : hint_range(0.0, 4.0) = 1.2;      // speed of the lapping bands

group_uniforms Interaction;
uniform float wave_time = 0.0;
// Pushed every frame by WaterManager.gd - do not rename these.
uniform vec4 ripple_data[16]; // xy = world contact point (x,z), z = spawn time (sim_time), w = strength
uniform int ripple_count : hint_range(0, 16) = 0;
uniform float sim_time = 0.0;
uniform float ripple_lifetime : hint_range(0.5, 30.0) = 6.0;
uniform float ripple_speed : hint_range(0.1, 20.0) = 2.2;
uniform float ripple_wavelength : hint_range(0.05, 5.0) = 0.7;
uniform float ripple_width : hint_range(0.05, 10.0) = 1.2;
uniform float ripple_amplitude : hint_range(0.0, 3.0) = 0.4;
// Stylized ripple rings: crisp foam-coloured lines drawn per pixel, using ripple_wavelength as the line spacing.
uniform float ripple_line_width : hint_range(0.1, 5.0) = 0.9;     // how many metres of the ring are visible (bigger = more lines)
uniform float ripple_line_threshold : hint_range(0.05, 0.95) = 0.3; // higher = thinner lines
uniform float ripple_line_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms Biomes;
// Pushed every update_interval by WaterBiomeSystem.gd - do not rename these.
uniform vec4 biome_data[8];   // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];   // x = wave height mult, y = wave frequency mult (1/wave_length_mult), z = wave speed mult, w = turbulence
uniform vec4 biome_ripple[8]; // x = ripple speed mult, y = ripple wavelength mult, z = ripple amplitude mult, w = unused
uniform vec4 biome_look[8];   // x = tint strength, y = foam amount mult, z = (unused now, was roughness add), w = POLLUTION add
uniform vec4 biome_tint[8];   // rgb = tint color, a = unused

varying vec3 v_world_pos;
varying float v_jacobian;
varying float v_extra_height;
varying vec4 v_biome_look;
varying vec3 v_biome_tint;
varying vec3 v_ripple_mult;   // biome ripple speed/wavelength/amplitude mults, so the per-pixel rings line up with the vertex rings

// ---------------------------------------------------------------------
// Hash / noise helpers  (unchanged: fbm() must match WaterManager.gd)
// ---------------------------------------------------------------------
float hash21(vec2 p) {
	p = mod(p, 289.0);
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Full 4-octave fbm - feeds vertex displacement, keep identical to the CPU port.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	return v;
}

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	return v;
}

float fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	return v;
}

vec2 rotate2(vec2 v, float rad) {
	float s = sin(rad);
	float c = cos(rad);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// View-space position of whatever the depth buffer holds at uv.
// (Forward+/Mobile, reverse-Z: ndc.z = depth. Compatibility: use depth * 2.0 - 1.0.)
vec3 scene_view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_texture, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// Ripple life envelope, shared by vertex() and fragment() (and mirrored in
// WaterManager.gd::_ripple_env). Short fade-in so a ripple never pops into
// existence, then a smoothstep ease-out: it holds its strength, then dissolves
// through a long soft tail with zero slope at the end - no cut-off.
float ripple_env(float age) {
	float u = clamp(age / max(ripple_lifetime, 0.001), 0.0, 1.0);
	float fade_out = 1.0 - u * u * (3.0 - 2.0 * u);   // smoothstep ease-out: holds strength, then dissolves with zero slope at both ends
	return smoothstep(0.0, 0.15, age) * fade_out;
}

// ---------------------------------------------------------------------
// Gerstner wave accumulation  (UNCHANGED)
// ---------------------------------------------------------------------
void accumulate_swell_wave(vec2 pos, float t, float wind_rad, vec4 chop_mult,
		float angle_deg, float base_wavelength, float steepness_base, float amp_scale, float speed_base, float wave_seed,
		inout vec3 offset, inout vec3 tangent, inout vec3 binormal,
		inout float dDx_dx, inout float dDx_dz, inout float dDz_dx, inout float dDz_dz) {

	float jitter_deg = (fbm(vec2(wave_seed, t * 0.015)) - 0.5) * 2.0 * wave_direction_jitter;
	float ang = radians(angle_deg + jitter_deg) + wind_rad;
	vec2 dir = vec2(cos(ang), sin(ang));

	float wavelength = max(base_wavelength * swell_wavelength_scale, 0.5);
	float category_amp = swell_amplitude * mix(1.0, chop_mult.x, 0.35);
	float speed_mult_biome = mix(1.0, chop_mult.z, 0.35);

	float nyquist_fade = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, wavelength);
	category_amp *= nyquist_fade;

	float k = 6.28318530718 / wavelength;
	float c = sqrt(9.8 / k) * speed_base * speed_mult_biome;
	float a = amp_scale * category_amp;
	float steepness = steepness_base * wave_choppiness;
	float f = k * (dot(dir, pos) - c * t * wave_speed);

	float sinf = sin(f);
	float cosf = cos(f);

	offset.x += steepness * a * dir.x * cosf;
	offset.z += steepness * a * dir.y * cosf;
	offset.y += a * sinf;

	float wa = k * a;
	tangent += vec3(
		-dir.x * dir.x * steepness * wa * sinf,
		dir.x * wa * cosf,
		-dir.x * dir.y * steepness * wa * sinf
	);
	binormal += vec3(
		-dir.x * dir.y * steepness * wa * sinf,
		dir.y * wa * cosf,
		-dir.y * dir.y * steepness * wa * sinf
	);

	float ksin = k * steepness * a * sinf;
	dDx_dx += -dir.x * dir.x * ksin;
	dDx_dz += -dir.x * dir.y * ksin;
	dDz_dx += -dir.y * dir.x * ksin;
	dDz_dz += -dir.y * dir.y * ksin;
}

void accumulate_chop_wave(vec2 pos, float t, float wind_rad, vec4 chop_mult, float chop_patch_mult,
		float angle_deg, float base_wavelength, float steepness_base, float amp_scale, float speed_base, float wave_seed,
		inout vec3 offset, inout vec3 tangent, inout vec3 binormal,
		inout float dDx_dx, inout float dDx_dz, inout float dDz_dx, inout float dDz_dz) {

	float jitter_deg = (fbm(vec2(wave_seed, t * 0.015)) - 0.5) * 2.0 * wave_direction_jitter;
	float ang = radians(angle_deg + jitter_deg) + wind_rad;
	vec2 dir = vec2(cos(ang), sin(ang));

	float wavelength = max(base_wavelength / max(chop_mult.y, 0.01), 0.5);
	float category_amp = chop_amplitude * chop_patch_mult * chop_mult.x;
	float speed_mult_biome = chop_mult.z;

	float nyquist_fade = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, wavelength);
	category_amp *= nyquist_fade;

	float k = 6.28318530718 / wavelength;
	float c = sqrt(9.8 / k) * speed_base * speed_mult_biome;
	float a = amp_scale * category_amp;
	float steepness = steepness_base * wave_choppiness;
	float f = k * (dot(dir, pos) - c * t * wave_speed);

	float sinf = sin(f);
	float cosf = cos(f);

	offset.x += steepness * a * dir.x * cosf;
	offset.z += steepness * a * dir.y * cosf;
	offset.y += a * sinf;

	float wa = k * a;
	tangent += vec3(
		-dir.x * dir.x * steepness * wa * sinf,
		dir.x * wa * cosf,
		-dir.x * dir.y * steepness * wa * sinf
	);
	binormal += vec3(
		-dir.x * dir.y * steepness * wa * sinf,
		dir.y * wa * cosf,
		-dir.y * dir.y * steepness * wa * sinf
	);

	float ksin = k * steepness * a * sinf;
	dDx_dx += -dir.x * dir.x * ksin;
	dDx_dz += -dir.x * dir.y * ksin;
	dDz_dx += -dir.y * dir.x * ksin;
	dDz_dz += -dir.y * dir.y * ksin;
}

// ---------------------------------------------------------------------
// vertex()  (UNCHANGED - byte-for-byte the previous version)
// ---------------------------------------------------------------------
void vertex() {
	vec2 pos_xz = VERTEX.xz;
	float t = wave_time;
	float wind_rad = radians(wind_direction_deg);
	float sc = 1.0 / max(meters_per_unit, 0.001);

	vec4 chop_mult = vec4(1.0, 1.0, 1.0, 0.0);   // x=height, y=freq(1/wavelength), z=speed, w=turbulence
	vec4 ripple_mult = vec4(1.0, 1.0, 1.0, 0.0); // x=speed, y=wavelength, z=amplitude, w=unused
	vec4 look_mix = vec4(0.0, 1.0, 0.0, 0.0);    // x=tint strength, y=foam mult, z=roughness add
	vec3 tint_mix = vec3(0.0);

	for (int i = 0; i < 8; i++) {
		if (i >= biome_count) {
			break;
		}
		vec2 center = biome_data[i].xy;
		float radius = biome_data[i].z;
		float blend = max(biome_data[i].w, 0.001);
		float dist = length(pos_xz - center);
		float w = 1.0 - smoothstep(radius, radius + blend, dist);
		chop_mult = mix(chop_mult, biome_chop[i], w);
		ripple_mult = mix(ripple_mult, biome_ripple[i], w);
		look_mix = mix(look_mix, biome_look[i], w);
		tint_mix = mix(tint_mix, biome_tint[i].rgb, w);
	}
	v_biome_look = look_mix;
	v_biome_tint = tint_mix;
	v_ripple_mult = ripple_mult.xyz;

	vec2 warp_seed = pos_xz * domain_warp_scale;
	vec2 warp = vec2(
		fbm(warp_seed + vec2(0.0, t * domain_warp_speed)),
		fbm(warp_seed + vec2(5.2, -t * domain_warp_speed))
	) - 0.5;
	vec2 warped_pos = pos_xz + warp * domain_warp_amount;

	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	float dDx_dx = 0.0;
	float dDx_dz = 0.0;
	float dDz_dx = 0.0;
	float dDz_dz = 0.0;

	float chop_patch = fbm(warped_pos * 0.015 + vec2(4.0, 9.0));
	float chop_patch_mult = mix(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, chop_patch);

	accumulate_swell_wave(warped_pos, t, wind_rad, chop_mult, 0.0, 85.0, 0.8, 1.0, 0.9, 0.0,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);
	accumulate_swell_wave(warped_pos, t, wind_rad, chop_mult, 24.0, 52.0, 0.7, 0.6, 1.05, 17.17,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);
	accumulate_chop_wave(warped_pos, t, wind_rad, chop_mult, chop_patch_mult, 61.0, 22.0, 0.45, 0.32, 1.3, 34.34,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);
	accumulate_chop_wave(warped_pos, t, wind_rad, chop_mult, chop_patch_mult, -37.0, 13.0, 0.35, 0.2, 1.5, 51.51,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);
	accumulate_chop_wave(warped_pos, t, wind_rad, chop_mult, chop_patch_mult, 104.0, 6.0, 0.22, 0.1, 1.9, 68.68,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);
	accumulate_chop_wave(warped_pos, t, wind_rad, chop_mult, chop_patch_mult, -73.0, 3.2, 0.14, 0.05, 2.2, 85.85,
		offset, tangent, binormal, dDx_dx, dDx_dz, dDz_dx, dDz_dz);

	float jacobian = (1.0 + dDx_dx) * (1.0 + dDz_dz) - (dDx_dz * dDz_dx);

	float extra_height = 0.0;
	vec2 extra_deriv = vec2(0.0);
	float e = 0.5;

	vec2 turb_freq = vec2(0.03) * max(chop_mult.y, 0.01);
	float turb_wavelength = 1.0 / max(turb_freq.x, 0.0001) / sc;
	float turb_nyquist_fade = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, turb_wavelength);

	vec2 uv_t = warped_pos * sc * turb_freq + vec2(t * 0.6, t * 0.45);
	float hT = fbm(uv_t) - 0.5;
	float hTX = fbm(uv_t + vec2(e * turb_freq.x, 0.0)) - 0.5;
	float hTZ = fbm(uv_t + vec2(0.0, e * turb_freq.y)) - 0.5;
	float turb_height = chop_amplitude * 1.5 * chop_mult.w * turb_nyquist_fade;
	extra_height += hT * turb_height;
	extra_deriv += vec2(hT - hTX, hT - hTZ) * (turb_height / e);

	float local_ripple_speed = ripple_speed * ripple_mult.x;
	// Mesh-safe ripple: the vertex grid can't represent a wavelength/width below a few
	// vertex spacings (it aliased into ragged blobs), so the DISPLACEMENT ring is clamped
	// up to what the mesh can hold. The fine detail is drawn per-pixel in fragment().
	float local_ripple_wavelength = max(ripple_wavelength * ripple_mult.y, mesh_vertex_spacing * 3.5);
	float local_ripple_width = max(ripple_width, mesh_vertex_spacing * 2.0);
	float k_r = TAU / local_ripple_wavelength;

	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) {
			break;
		}
		vec2 rp = ripple_data[i].xy;
		float spawn = ripple_data[i].z;
		float strength = ripple_data[i].w;
		float age = sim_time - spawn;

		float valid = step(0.0, age) * step(age, ripple_lifetime) * step(0.0001, strength);

		vec2 to_point = (pos_xz - rp) * sc;
		float dist = length(to_point);
		float wavefront = age * local_ripple_speed;
		float bx = (dist - wavefront) / (local_ripple_width * (1.0 + max(age, 0.0) * 0.25));   // ring widens as it travels
		float band = exp(-bx * bx);   // was pow(bx, 2.0): undefined for bx < 0 in GLSL -> NaN -> vanishing water

		float decay = strength * ripple_env(age) * inversesqrt(1.0 + max(wavefront, 0.0) * 0.5);
		float phase = (dist - wavefront) * k_r;
		float amp = ripple_amplitude * ripple_mult.z * decay * band * valid;

		extra_height += sin(phase) * amp;

		vec2 dir_to = to_point / max(dist, 0.0001);
		float dh = cos(phase) * k_r * amp;
		extra_deriv += dir_to * dh;
	}

	tangent.y += extra_deriv.x;
	binormal.y += extra_deriv.y;
	offset.y += extra_height;

	VERTEX += offset;
	NORMAL = normalize(cross(binormal, tangent));

	v_jacobian = jacobian;
	v_extra_height = extra_height;
	v_world_pos = VERTEX;
}

// ---------------------------------------------------------------------
// fragment()  - stylized
// ---------------------------------------------------------------------
void fragment() {
	vec3 wpos = v_world_pos;
	float t = wave_time;
	float sc = 1.0 / max(meters_per_unit, 0.001);
	vec4 look = v_biome_look;   // x = tint strength, y = foam mult, z = unused, w = pollution add
	float k_biome = clamp(look.x, 0.0, 1.0);
	float pollution = clamp(pollution_amount + look.w, 0.0, 1.0);

	// ------------------------------------------------------------------
	// 1. Shading normal: the Gerstner normal pulled toward straight up so the
	//    lambert shading stays nearly uniform (flat-looking water).
	// ------------------------------------------------------------------
	vec3 n_geo = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n_world = normalize(mix(n_geo, vec3(0.0, 1.0, 0.0), normal_flatten));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// ------------------------------------------------------------------
	// 2. Depth: metres of water between the surface and whatever is behind it
	// ------------------------------------------------------------------
	float water_z = -VERTEX.z;
	vec3 sp0 = scene_view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = clamp(-sp0.z - water_z, 0.0, 400.0);

	float murk = 1.0 + pollution * pollution_murk;
	float depth_t = 1.0 - exp(-thick * murk / max(depth_fade_distance, 0.05));
	if (depth_bands > 0) {
		float b = float(depth_bands);
		depth_t = clamp(floor(depth_t * b) / max(b - 1.0, 1.0), 0.0, 1.0);
	}

	// ------------------------------------------------------------------
	// 3. Water colour: shallow -> deep gradient, soft patches, biome tint, crest tint
	// ------------------------------------------------------------------
	vec3 water_col = mix(color_shallow.rgb, color_deep.rgb, depth_t);

	float var_n = fbm2(wpos.xz * color_variation_scale + vec2(t * color_variation_speed, -t * color_variation_speed * 0.6));
	water_col = mix(water_col, color_variation_tint.rgb, smoothstep(0.3, 0.7, var_n) * color_variation_strength);

	vec3 biome_col = v_biome_tint * mix(0.9, 0.5, depth_t);
	water_col = mix(water_col, biome_col, k_biome);

	float wave_h = wpos.y - NODE_POSITION_WORLD.y;
	float h_ref = max(swell_amplitude * 0.8 + chop_amplitude, 0.15);
	float crest = smoothstep(0.15, 1.0, wave_h / h_ref + clamp(1.0 - v_jacobian, 0.0, 1.0) * 0.5);
	vec3 crest_col = mix(color_crest.rgb, v_biome_tint * 0.9, k_biome);
	water_col = mix(water_col, crest_col, crest * crest_amount);

	// ------------------------------------------------------------------
	// 4. See-through: whatever is under the water fades out with depth.
	//    No distortion, no blur - just a clean tinted fade.
	// ------------------------------------------------------------------
	float see = exp(-thick * murk / max(clarity_distance, 0.05)) * see_through;
	vec3 scene_col = texture(screen_texture, SCREEN_UV).rgb;
	vec3 hue = water_col / max(max(water_col.r, max(water_col.g, water_col.b)), 0.001);
	vec3 seen = scene_col * mix(vec3(1.0), hue, see_through_tint);

	vec3 albedo = water_col * (1.0 - see);
	vec3 emit = seen * see;

	// ------------------------------------------------------------------
	// 5. Surface films (pollution): flat patches with crisp edges
	// ------------------------------------------------------------------
	float pol_on = smoothstep(0.0, 0.12, pollution);
	float scum_n = fbm3(wpos.xz * scum_scale + vec2(t * 0.004, -t * 0.003) + vec2(71.0, 13.0));
	float scum_thr = mix(0.66, 0.42, pollution);
	float scum = smoothstep(scum_thr, scum_thr + 0.04, scum_n) * pol_on * scum_strength;
	float slick_n = fbm3(wpos.xz * slick_scale + vec2(-t * 0.006, t * 0.004));
	float slick_thr = mix(0.68, 0.44, pollution);
	float slick = smoothstep(slick_thr, slick_thr + 0.05, slick_n) * pol_on * (1.0 - scum) * slick_strength;

	// ------------------------------------------------------------------
	// 6. Foam: wave-crest fold, ripple crests, shore / hull contact, ripple lines
	// ------------------------------------------------------------------
	float threshold_noise = (fbm2(wpos.xz * 0.04 + vec2(12.3, -7.1)) - 0.5) * 2.0 * foam_threshold_jitter;
	float fold_amount = (foam_jacobian_threshold + threshold_noise) - v_jacobian;
	float foam_edge = smoothstep(-foam_edge_softness, foam_edge_softness, fold_amount);

	float extra_ref = max(ripple_amplitude, 0.001);
	float extra_norm = clamp(v_extra_height / extra_ref, -1.0, 1.0);
	float ripple_crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, extra_norm);
	float fold_mask = max(foam_edge, ripple_crest);

	vec2 foam_warp = (vec2(
		fbm2(wpos.xz * sc * 0.02 + vec2(3.3, 8.8)),
		fbm2(wpos.xz * sc * 0.02 + vec2(-4.1, 1.7))
	) - 0.5) * foam_warp_amount;

	float foam_pattern;
	if (use_custom_foam_texture) {
		vec2 uv_a = wpos.xz * sc * foam_uv_scale * 0.1 + vec2(t * foam_speed, 0.0) + foam_warp;
		vec2 uv_b = rotate2(wpos.xz * sc, radians(37.0)) * foam_uv_scale_2 * 0.1 - vec2(0.0, t * foam_speed * 0.8) + foam_warp * 0.6;
		float tex_a = texture(foam_texture, uv_a).r;
		float tex_b = texture(foam_texture, uv_b).r;
		foam_pattern = clamp(tex_a * 0.65 + tex_b * 0.65, 0.0, 1.0);
	} else {
		vec2 fuv = wpos.xz * sc * foam_uv_scale * 0.2 + vec2(t * foam_speed, 0.0) + foam_warp;
		foam_pattern = fbm3(fuv * 3.0);
	}

	vec2 detail_uv = wpos.xz * foam_noise_scale + vec2(t * foam_scroll_speed, t * foam_scroll_speed * 0.7);
	float foam_detail = fbm3(detail_uv + vec2(50.0));

	float foam_thr = mix(0.6, 0.12, foam_amount);
	float foam_soft = mix(0.2, 0.02, foam_crispness);

	float foam_field = fold_mask * mix(0.5, 1.0, foam_detail) * foam_pattern * 1.6 * look.y;
	float foam_waves = smoothstep(max(foam_thr - foam_soft, 0.01), foam_thr + foam_soft, foam_field);

	float shore_foam = 0.0;
	if (enable_shore_foam) {
		float sd = max(shore_foam_distance, 0.01);
		float sn = fbm2(wpos.xz * 0.5 + vec2(t * 0.08, -t * 0.05));
		float lip = 1.0 - smoothstep(0.0, sd * (0.55 + 0.9 * sn), thick);
		float bands = sin(thick / sd * 5.0 - t * shore_band_speed + sn * 5.0) * 0.5 + 0.5;
		bands = smoothstep(0.6, 0.9, bands) * (1.0 - smoothstep(0.0, sd * 3.0, thick)) * 0.7;
		float shore = clamp(lip + bands, 0.0, 1.0) * look.y;
		float s_thr = foam_thr * 0.6;
		shore_foam = smoothstep(max(s_thr - foam_soft, 0.01), s_thr + foam_soft, shore * (0.4 + foam_pattern * 1.2));
	}

	// Ripple rings from spawn_ripple(): crisp foam-coloured lines instead of lit normals.
	float ripple_lines = 0.0;
	float r_speed = ripple_speed * v_ripple_mult.x;
	float r_wl = max(ripple_wavelength * v_ripple_mult.y, 0.05);
	float r_k = TAU / r_wl;
	float r_fade = 1.0 - smoothstep(0.15, 0.4, length(fwidth(wpos.xz)) * sc / r_wl);   // fade out before they alias
	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) {
			break;
		}
		float r_age = sim_time - ripple_data[i].z;
		if (r_age < 0.0 || r_age > ripple_lifetime) {
			continue;   // depends only on uniforms -> same for every pixel, so this is cheap
		}
		vec2 to_p = (wpos.xz - ripple_data[i].xy) * sc;
		float r_dist = length(to_p);
		float r_front = r_age * r_speed;
		float r_bx = (r_dist - r_front) / (ripple_line_width * (1.0 + r_age * 0.25));
		float r_env = clamp(ripple_data[i].w, 0.0, 1.0) * clamp(v_ripple_mult.z, 0.0, 2.0)
				* ripple_env(r_age) * inversesqrt(1.0 + r_front * 0.5);
		float r_wave = 0.5 + 0.5 * cos((r_dist - r_front) * r_k);
		ripple_lines = max(ripple_lines, r_wave * exp(-r_bx * r_bx) * r_env);
	}
	ripple_lines = smoothstep(max(ripple_line_threshold - foam_soft, 0.01), ripple_line_threshold + foam_soft, ripple_lines * r_fade)
			* ripple_line_strength;

	float foam = clamp(max(max(foam_waves, shore_foam), ripple_lines), 0.0, 1.0);

	// ------------------------------------------------------------------
	// 7. Composite: oil patch -> scum -> foam (each covers the last)
	// ------------------------------------------------------------------
	albedo = mix(albedo, slick_color.rgb, slick);
	emit *= 1.0 - slick;

	albedo = mix(albedo, scum_color.rgb, scum);
	emit *= 1.0 - scum;

	albedo = mix(albedo, color_foam.rgb, foam);
	emit *= 1.0 - foam;

	ALBEDO = albedo;
	EMISSION = emit;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
