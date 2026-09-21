shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords, diffuse_lambert, specular_schlick_ggx;

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

group_uniforms Water_Body;
// Light that SURVIVES travelling absorption_distance metres through clean-ish water.
// Low red = the classic blue/green shift with depth. Push toward brown/green for murk.
uniform vec4 absorption_color : source_color = vec4(0.30, 0.60, 0.48, 1.0);
uniform float absorption_distance : hint_range(0.5, 60.0) = 5.0;
// Colour of the water body itself (what you see in deep water where nothing shows through).
uniform vec4 color_scatter : source_color = vec4(0.035, 0.18, 0.16, 1.0);
// Lighter, more saturated colour where light passes through thin wave crests.
uniform vec4 color_crest_scatter : source_color = vec4(0.14, 0.40, 0.32, 1.0);
uniform float crest_scatter_amount : hint_range(0.0, 1.0) = 0.4;
// Big slow patches of a second tint (algae bloom / sediment) so open water isn't flat.
uniform vec4 color_variation_tint : source_color = vec4(0.10, 0.20, 0.05, 1.0);
uniform float color_variation_scale : hint_range(0.0005, 0.05) = 0.005;
uniform float color_variation_speed : hint_range(0.0, 0.05) = 0.003;
uniform float color_variation_strength : hint_range(0.0, 1.0) = 0.35;

group_uniforms Surface;
uniform float water_roughness : hint_range(0.0, 0.5) = 0.06;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float far_roughen_start : hint_range(10.0, 2000.0) = 80.0;   // distance where specular starts softening (kills far shimmer)
uniform float far_roughen_end : hint_range(20.0, 4000.0) = 500.0;

group_uniforms Reflections;
// Cheap screen-space reflection of whatever is above the water (boats, pilings, islands).
// Misses fall back to Godot's normal sky reflection.
uniform bool enable_reflections = true;
uniform float reflection_strength : hint_range(0.0, 2.0) = 1.0;
uniform float reflection_min : hint_range(0.0, 0.6) = 0.12;      // reflectivity looking straight down (real water is ~0.02; higher = more obvious)
uniform float reflection_blur : hint_range(0.0, 0.3) = 0.05;     // extra blur per metre of reflected distance (softens and hides the shortcuts)
uniform float reflection_step : hint_range(0.1, 3.0) = 0.5;      // first march step in metres; steps grow 15% each

group_uniforms Detail_Normals;
uniform float detail_height : hint_range(0.0, 1.0) = 0.14;        // ripple height in metres; bigger = choppier glints
uniform float detail_scale : hint_range(0.05, 4.0) = 0.55;        // ripples per metre
uniform float detail_speed : hint_range(0.0, 2.0) = 0.25;
uniform float detail_fade_start : hint_range(5.0, 500.0) = 40.0;  // detail fades out between these camera distances
uniform float detail_fade_end : hint_range(10.0, 1000.0) = 170.0;

group_uniforms Refraction_And_Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform bool enable_refraction = true;
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.06;
uniform float underwater_blur : hint_range(0.0, 1.0) = 0.25;      // extra blur per metre of water
uniform float caustics_strength : hint_range(0.0, 4.0) = 1.2;     // set to 0 at night / heavy overcast from script
uniform float caustics_scale : hint_range(0.05, 3.0) = 0.6;
uniform float caustics_depth : hint_range(0.5, 20.0) = 4.0;       // metres until caustics fade out

group_uniforms Pollution;
uniform float pollution_amount : hint_range(0.0, 1.0) = 0.35;     // global; biome_look.w is added on top
uniform float pollution_murk : hint_range(0.0, 8.0) = 3.0;        // how much faster light dies in fully polluted water
uniform float slick_scale : hint_range(0.0005, 0.1) = 0.02;
uniform float slick_sheen : hint_range(0.0, 1.0) = 0.7;           // oil-film iridescence strength
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
uniform float foam_crispness : hint_range(0.0, 1.0) = 0.6;        // 0 = soft/misty, 1 = hard cel-shaded edge (suits blocky models)
uniform float foam_dither_amount : hint_range(0.0, 0.2) = 0.04;
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
uniform float ripple_detail_height : hint_range(0.0, 0.3) = 0.035;  // per-pixel ripple height (m) at the true ripple_wavelength; the mesh can't show these

group_uniforms Biomes;
// Pushed every update_interval by WaterBiomeSystem.gd - do not rename these.
uniform vec4 biome_data[8];   // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];   // x = wave height mult, y = wave frequency mult (1/wave_length_mult), z = wave speed mult, w = turbulence
uniform vec4 biome_ripple[8]; // x = ripple speed mult, y = ripple wavelength mult, z = ripple amplitude mult, w = unused
uniform vec4 biome_look[8];   // x = tint strength, y = foam amount mult, z = roughness add, w = POLLUTION add (new, optional)
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

// ---------------------------------------------------------------------
// Fragment-only helpers (no CPU equivalent needed)
// ---------------------------------------------------------------------

// Value noise + analytic gradient. Returns (value, d/dx, d/dy).
vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float k = a - b - c + d;
	float v = a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y;
	vec2 g = du * vec2((b - a) + k * u.y, (c - a) + k * u.x);
	return vec3(v, g);
}

// 3-octave fbm with analytic gradient (w.r.t. p). Each octave is rotated so the
// value-noise grid doesn't show. Returns (value - mean, d/dx, d/dy).
vec3 fbm_d(vec2 p) {
	mat2 R = mat2(vec2(1.6, -1.2), vec2(1.2, 1.6));   // scale 2, rotate ~37 degrees
	mat2 m = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	float v = 0.0;
	vec2 g = vec2(0.0);
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		vec3 n = noised(m * p + vec2(float(i) * 7.3, float(i) * 3.1));
		v += amp * n.x;
		g += amp * (n.yz * m);
		m = R * m;
		amp *= 0.5;
	}
	return vec3(v - 0.4375, g);
}

// Bright net-like caustic lines from two counter-scrolling ridged noises.
float caustic_pattern(vec2 p, float t) {
	float a = 1.0 - abs(value_noise(p * 1.7 + vec2(t * 0.30, t * 0.18)) * 2.0 - 1.0);
	float b = 1.0 - abs(value_noise(rotate2(p, 0.9) * 2.3 + vec2(-t * 0.22, t * 0.27)) * 2.0 - 1.0);
	return pow(a * b, 5.0) * 3.0;
}

// View-space position of whatever the depth buffer holds at uv.
// (Forward+/Mobile, reverse-Z: ndc.z = depth. Compatibility: use depth * 2.0 - 1.0.)
vec3 scene_view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_texture, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// Cheap screen-space reflection. Marches the reflected ray in view space (24 steps,
// growing 15% each) and compares its depth with the depth buffer. On a hit, returns
// the screen colour there (blurred with distance) and a confidence that fades near the
// screen edges and for far hits. No hit = confidence 0 -> sky reflection is used.
vec4 trace_reflection(vec3 P, vec3 R, mat4 proj, mat4 inv_proj) {
	float step_len = max(reflection_step, 0.05);
	vec3 ray = P;
	for (int i = 0; i < 24; i++) {
		ray += R * step_len;
		step_len *= 1.15;
		vec4 c = proj * vec4(ray, 1.0);
		if (c.w <= 0.0) {
			break;   // ray went behind the camera plane
		}
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;   // left the screen - nothing to reflect
		}
		vec3 sp = scene_view_pos(uv, inv_proj);
		float diff = (-ray.z) - (-sp.z);   // > 0 means the ray is now behind visible geometry
		if (diff > 0.0 && diff < step_len * 2.0 + 0.3) {
			vec2 e = min(uv, 1.0 - uv);
			float edge = smoothstep(0.0, 0.12, min(e.x, e.y));
			float far_fade = 1.0 - smoothstep(0.55, 1.0, float(i) / 24.0);
			float lod = clamp(length(ray - P) * reflection_blur, 0.0, 4.0);
			return vec4(textureLod(screen_texture, uv, lod).rgb, edge * far_fade);
		}
	}
	return vec4(0.0);
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
// fragment()
// ---------------------------------------------------------------------
void fragment() {
	vec3 wpos = v_world_pos;
	float t = wave_time;
	float sc = 1.0 / max(meters_per_unit, 0.001);
	vec4 look = v_biome_look;   // x = tint strength, y = foam mult, z = roughness add, w = pollution add
	float k_biome = clamp(look.x, 0.0, 1.0);
	float pollution = clamp(pollution_amount + look.w, 0.0, 1.0);
	float cam_dist = length(VERTEX);
	vec3 view_dir = normalize(VIEW);

	// ------------------------------------------------------------------
	// 1. Pollution masks (surface films). Computed first because they calm
	//    the ripples underneath them: oil and scum really do damp small waves.
	// ------------------------------------------------------------------
	float pol_on = smoothstep(0.0, 0.12, pollution);
	float scum_n = fbm3(wpos.xz * scum_scale + vec2(t * 0.004, -t * 0.003) + vec2(71.0, 13.0));
	float scum_thr = mix(0.66, 0.42, pollution);
	float scum = smoothstep(scum_thr, scum_thr + 0.04, scum_n) * pol_on * scum_strength;
	float slick_n = fbm3(wpos.xz * slick_scale + vec2(-t * 0.006, t * 0.004));
	float slick_thr = mix(0.68, 0.44, pollution);
	float slick = smoothstep(slick_thr, slick_thr + 0.20, slick_n) * pol_on * (1.0 - scum);

	// ------------------------------------------------------------------
	// 2. Detail normals: two scrolling layers of analytic-gradient noise,
	//    added to the mesh (Gerstner) normal in world space.
	// ------------------------------------------------------------------
	vec3 n_geo = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float wind_rad = radians(wind_direction_deg);
	vec2 wind_dir = vec2(cos(wind_rad), sin(wind_rad));
	float dfade = 1.0 - smoothstep(detail_fade_start, max(detail_fade_end, detail_fade_start + 1.0), cam_dist);

	vec2 d_uv1 = wpos.xz * sc * detail_scale + wind_dir * t * detail_speed;
	vec2 d_uv2 = rotate2(wpos.xz * sc, 0.9) * detail_scale * 2.1 + vec2(-wind_dir.y, wind_dir.x) * t * detail_speed * 1.3;
	vec2 d_uv3 = wpos.xz * sc * detail_scale * 0.22 + wind_dir * t * detail_speed * 0.5;
	vec3 dn1 = fbm_d(d_uv1);
	vec3 dn2 = fbm_d(d_uv2);
	vec3 dn3 = fbm_d(d_uv3);
	vec2 slope1 = dn1.yz * detail_scale * sc;
	vec2 slope2 = rotate2(dn2.yz, -0.9) * detail_scale * sc * 2.1;
	vec2 slope3 = dn3.yz * detail_scale * sc * 0.22;
	// Anti-aliasing: fade each layer out once one screen pixel covers more than ~half
	// its finest wavelength. Grazing angles stretch a pixel a long way along the water,
	// which is what causes the "stippled hatching" on mid-distance water otherwise.
	float foot = length(fwidth(wpos.xz)) * sc * detail_scale;
	float fade1 = 1.0 - smoothstep(0.06, 0.20, foot);
	float fade2 = 1.0 - smoothstep(0.03, 0.10, foot);
	vec2 slope = (slope1 * fade1 + slope2 * 0.5 * fade2 + slope3 * 3.0) * detail_height;
	slope *= dfade * (1.0 - 0.7 * slick) * (1.0 - 0.85 * scum);

	// Fine ripple rings from spawn_ripple(), drawn per pixel at their TRUE wavelength
	// (the mesh draws the smooth big ring; this adds the crisp detail on top of it).
	float r_speed = ripple_speed * v_ripple_mult.x;
	float r_wl = max(ripple_wavelength * v_ripple_mult.y, 0.05);
	float r_k = TAU / r_wl;
	float r_width = max(ripple_width, mesh_vertex_spacing * 2.0);
	float r_fade = 1.0 - smoothstep(0.15, 0.4, length(fwidth(wpos.xz)) * sc / r_wl);   // fade out before they alias
	vec2 rslope = vec2(0.0);
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
		float r_bx = (r_dist - r_front) / (r_width * (1.0 + r_age * 0.25));
		float r_amp = ripple_detail_height * v_ripple_mult.z * ripple_data[i].w * ripple_env(r_age)
				* inversesqrt(1.0 + r_front * 0.5) * exp(-r_bx * r_bx);
		float r_phase = (r_dist - r_front) * r_k;
		rslope += (to_p / max(r_dist, 0.0001)) * (cos(r_phase) * r_k * r_amp * sc);
	}
	slope += rslope * r_fade;

	vec3 n_world = normalize(vec3(n_geo.x - slope.x * n_geo.y, n_geo.y, n_geo.z - slope.y * n_geo.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float ndotv = clamp(dot(NORMAL, view_dir), 0.02, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, 5.0);

	// ------------------------------------------------------------------
	// 3. Depth: how much water is between the surface and whatever is behind it
	// ------------------------------------------------------------------
	float water_z = -VERTEX.z;
	vec3 sp0 = scene_view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick0 = max(-sp0.z - water_z, 0.0);            // view-space water thickness at this pixel (shore foam + refraction gating)

	vec2 uv_r = SCREEN_UV;
	vec3 sp_r = sp0;
	if (enable_refraction) {
		// Distort by how much the normal differs from a perfectly flat surface,
		// otherwise the camera pitch would shift the whole picture.
		vec2 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 off = (NORMAL.xy - up_v) * refraction_strength;
		off *= clamp(thick0 * 0.5, 0.0, 1.0) / (1.0 + cam_dist * 0.02);
		vec2 uv_try = clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998));
		vec3 sp_try = scene_view_pos(uv_try, INV_PROJECTION_MATRIX);
		// If the distorted lookup hit something IN FRONT of the water (a hull, a pier),
		// keep the undistorted lookup - otherwise you get smeared edges around boats.
		float ok = step(water_z, -sp_try.z);
		uv_r = mix(SCREEN_UV, uv_try, ok);
		sp_r = mix(sp0, sp_try, ok);
	}

	float thick = max(-sp_r.z - water_z, 0.0);
	float ray_len = min(thick / max(abs(view_dir.z), 0.2), 400.0);   // metres of water along the view ray

	// ------------------------------------------------------------------
	// 4. Water colour: absorption (what shows through) + in-scatter (body colour)
	// ------------------------------------------------------------------
	vec3 trans_col = mix(absorption_color.rgb, clamp(v_biome_tint * 1.5 + 0.06, 0.02, 1.0), k_biome * 0.7);
	float murk = 1.0 + pollution * pollution_murk;
	vec3 T = pow(clamp(trans_col, vec3(0.002), vec3(1.0)), vec3(ray_len * murk / max(absorption_distance, 0.05)));

	float var_n = fbm2(wpos.xz * color_variation_scale + vec2(t * color_variation_speed, -t * color_variation_speed * 0.6));
	vec3 scatter_col = mix(color_scatter.rgb, color_variation_tint.rgb, smoothstep(0.3, 0.7, var_n) * color_variation_strength);
	scatter_col = mix(scatter_col, v_biome_tint * 0.55, k_biome);

	float wave_h = wpos.y - NODE_POSITION_WORLD.y;
	float h_ref = max(swell_amplitude * 0.8 + chop_amplitude, 0.15);
	float crest = smoothstep(0.15, 1.0, wave_h / h_ref + clamp(1.0 - v_jacobian, 0.0, 1.0) * 0.5);
	vec3 crest_col = mix(color_crest_scatter.rgb, v_biome_tint * 0.9, k_biome);
	scatter_col = mix(scatter_col, crest_col, crest * crest_scatter_amount);

	// Refracted scene, blurred with depth, with caustics on whatever is submerged.
	vec3 scene_col = vec3(0.0);
	vec3 body = vec3(1.0);
	if (enable_refraction) {
		float lod = clamp(ray_len * underwater_blur, 0.0, 5.0);
		scene_col = textureLod(screen_texture, uv_r, lod).rgb;

		vec3 s_world = (INV_VIEW_MATRIX * vec4(sp_r, 1.0)).xyz;
		float vdepth = wpos.y - s_world.y;
		float cfade = smoothstep(0.0, 0.3, vdepth) * exp(-max(vdepth, 0.0) / max(caustics_depth, 0.1)) * (1.0 - pollution * 0.6);
		float c = caustic_pattern(s_world.xz * sc * caustics_scale, t);
		scene_col *= 1.0 + c * caustics_strength * cfade;

		body = vec3(1.0) - T;
	}

	vec3 albedo = scatter_col * body;
	vec3 emit = scene_col * T * (1.0 - fresnel);   // (1 - fresnel): the reflected part is added by PBR, keep energy sane
	float metallic = 0.0;
	float rough = water_roughness;

	// ------------------------------------------------------------------
	// 5. Foam: wave-crest fold, ripple rings, shore / hull contact
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
	float dither = (hash21(wpos.xz * 3.7 + t) - 0.5) * foam_dither_amount;

	float foam_field = fold_mask * mix(0.5, 1.0, foam_detail) * foam_pattern * 1.6 * look.y;
	float foam_waves = smoothstep(max(foam_thr - foam_soft, 0.01), foam_thr + foam_soft, foam_field + dither);

	float shore_foam = 0.0;
	if (enable_shore_foam) {
		float sd = max(shore_foam_distance, 0.01);
		float sn = fbm2(wpos.xz * 0.5 + vec2(t * 0.08, -t * 0.05));
		float lip = 1.0 - smoothstep(0.0, sd * (0.55 + 0.9 * sn), thick0);
		float bands = sin(thick0 / sd * 5.0 - t * shore_band_speed + sn * 5.0) * 0.5 + 0.5;
		bands = smoothstep(0.6, 0.9, bands) * (1.0 - smoothstep(0.0, sd * 3.0, thick0)) * 0.7;
		float shore = clamp(lip + bands, 0.0, 1.0) * look.y;
		float s_thr = foam_thr * 0.6;
		shore_foam = smoothstep(max(s_thr - foam_soft, 0.01), s_thr + foam_soft, shore * (0.4 + foam_pattern * 1.2) + dither);
	}
	float foam = clamp(max(foam_waves, shore_foam), 0.0, 1.0);

	// ------------------------------------------------------------------
	// 6. Composite surface layers: oil slick -> scum -> foam (each covers the last)
	// ------------------------------------------------------------------
	// Oil: thin-film colour that shifts with angle and film thickness. A little
	// "metallic" tints the sky reflection with that colour (and stays night-safe,
	// since it's a reflection, not an emission).
	float sheen = slick * slick_sheen;
	float film_phase = fbm2(wpos.xz * slick_scale * 3.0 + vec2(17.0, 5.0)) * 2.2 + (1.0 - ndotv) * 1.4 + t * 0.02;
	vec3 film = 0.5 + 0.5 * cos(TAU * (vec3(film_phase) + vec3(0.0, 0.33, 0.67)));
	film = mix(vec3(0.5), film, 0.65);                              // muted, not neon
	film *= mix(0.45, 1.0, 1.0 - ndotv);                           // strongest at grazing angles, like the real thing
	albedo = mix(albedo, albedo * 0.5 + film * 0.3, sheen);
	emit *= 1.0 - sheen * 0.55;
	metallic = sheen * 0.45;
	rough = mix(rough, 0.03, sheen);

	albedo = mix(albedo, scum_color.rgb, scum);
	emit *= 1.0 - scum;
	metallic *= 1.0 - scum;
	rough = mix(rough, 0.85, scum);

	albedo = mix(albedo, color_foam.rgb, foam);
	emit *= 1.0 - foam;
	metallic *= 1.0 - foam;
	rough = mix(rough, 0.8, foam);

	// ------------------------------------------------------------------
	// 7. Reflection of what's above the water. Replaces the sky reflection where it
	//    hits something (SPECULAR is dialled down there so the two don't stack).
	//    Foam and scum are rough, so they don't mirror.
	// ------------------------------------------------------------------
	float refl_w = 0.0;
	if (enable_reflections) {
		vec3 R = reflect(-view_dir, NORMAL);
		vec3 R_world = (INV_VIEW_MATRIX * vec4(R, 0.0)).xyz;
		if (R_world.y > 0.02) {
			vec4 rf = trace_reflection(VERTEX, R, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
			float refl_f = clamp(reflection_min + (1.0 - reflection_min) * pow(1.0 - ndotv, 3.0), 0.0, 1.0) * reflection_strength;
			refl_w = clamp(refl_f, 0.0, 1.0) * rf.a * smoothstep(0.02, 0.15, R_world.y) * (1.0 - foam) * (1.0 - scum * 0.85);
			emit = emit * (1.0 - refl_w) + rf.rgb * refl_w;
		}
	}

	float far_rough = smoothstep(far_roughen_start, max(far_roughen_end, far_roughen_start + 1.0), cam_dist) * 0.35;

	ALBEDO = albedo;
	EMISSION = emit;
	METALLIC = metallic;
	ROUGHNESS = clamp(rough + look.z + far_rough, 0.0, 1.0);
	SPECULAR = specular_amount * (1.0 - foam * 0.8) * (1.0 - min(refl_w * 3.0, 0.85));
}
