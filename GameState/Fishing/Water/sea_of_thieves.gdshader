shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords, diffuse_lambert, specular_schlick_ggx;

// ============================================================================
// PERFORMANCE NOTES (read this before touching the internals):
//
// 1. The 6-wave Gerstner loop was manually unrolled into 6 explicit calls to
//    accumulate_swell_wave()/accumulate_chop_wave(). No loop, no dynamic array
//    indexing, no if(is_swell) branch per wave (swell/chop are now separate
//    functions instead of one function with a bool check). This is pure
//    restructuring - identical math, identical output to the original loop.
//
// 2. Noise quality is scoped by WHERE it's used, not cut everywhere equally:
//      - Anything that feeds VERTEX displacement (wave direction jitter,
//        domain warp, chop-patch modulation, turbulence height) keeps the
//        full 4-octave fbm(), unchanged from the original. These values are
//        also reproduced on the CPU in WaterManager.gd for buoyancy height
//        queries (get_water_height_at()) - if the shader and the CPU port
//        disagree on octave count, floating objects visibly settle off the
//        real wave surface, and reducing jitter's noise quality in
//        particular makes the whole wave field's direction drift in an
//        obviously repeating cycle instead of wandering irregularly. Both
//        problems are worse than the perf win, so this noise stays as-is.
//      - Fragment-only cosmetics with no CPU equivalent (foam warp UVs,
//        foam-threshold jitter, the procedural foam fallback pattern) use
//        fbm2 (2 octaves) or fbm3 (3 octaves) instead of 4. This is where
//        cutting octaves is actually safe and where it matters most for
//        perf, since the fragment shader runs per-pixel - far more
//        invocations than the vertex shader on the same mesh.
//
// 3. Per-vertex/per-fragment *varying* branches (continue on ripple age,
//    continue on biome weight, if(chop_mult.w > 0.01) for turbulence) were
//    replaced with branchless multiply-by-zero math, since those conditions
//    differ across neighboring vertices/fragments and cause real divergence.
//    These are exact algebraic equivalents of the original branches, not
//    approximations - no visual or physics difference.
//
// 4. Branches that stayed: `if (i >= biome_count) break;`, `if (i >=
//    ripple_count) break;`, `if (use_custom_foam_texture)`, `if
//    (enable_shore_foam)`. These are uniform (same value for every
//    vertex/fragment in the draw call), so the GPU takes one coherent path
//    for the whole draw - cheap by construction. Removing them would either
//    do nothing (the break; case) or force an unconditional texture sample
//    that's currently skipped entirely (the two bool cases), which would be
//    a regression, not an optimization.
// ============================================================================

group_uniforms Waves;
uniform float swell_amplitude : hint_range(0.0, 12.0) = 3.2;        // height of big rolling waves (meters, real units)
uniform float swell_wavelength_scale : hint_range(0.2, 4.0) = 1.0;  // scales how far apart swell crests are
uniform float chop_amplitude : hint_range(0.0, 2.0) = 0.35;         // height of small wind-driven surface waves
uniform float wave_speed     : hint_range(0.0, 3.0) = 1.0;
uniform float wave_choppiness: hint_range(0.0, 1.2) = 0.9;          // sharpens wave peaks (steepness ratio, NOT height)
uniform float wind_direction_deg : hint_range(0.0, 360.0) = 30.0;
uniform float wave_direction_jitter : hint_range(0.0, 60.0) = 20.0; // degrees; slow per-wave direction wander
uniform float chop_patchiness : hint_range(0.0, 1.0) = 0.5;         // spatial variation of chop intensity (wind gust patches)

group_uniforms Large_Scale_Variation;
uniform float domain_warp_amount : hint_range(0.0, 100.0) = 35.0;   // meters of positional distortion fed into the wave field
uniform float domain_warp_scale : hint_range(0.0005, 0.05) = 0.004; // lower = bigger, slower-changing warp regions
uniform float domain_warp_speed : hint_range(0.0, 0.2) = 0.02;

group_uniforms Scale;
uniform float meters_per_unit : hint_range(0.001, 100.0) = 1.0;     // used by ripples/biomes/foam UV, matches WaterManager.gd
uniform float mesh_vertex_spacing : hint_range(0.05, 20.0) = 1.25;  // world-space distance between adjacent mesh vertices (500m quad / 400 subdivisions ~= 1.25). Waves shorter than ~2x this alias into a visible grid on the surface - set this to match your actual mesh so the fade below kicks in at the right point.

group_uniforms Colors;
uniform vec4 color_deep     : source_color = vec4(0.015, 0.16, 0.28, 1.0);
uniform vec4 color_shallow  : source_color = vec4(0.04, 0.45, 0.48, 1.0);
uniform vec4 color_crest    : source_color = vec4(0.45, 0.80, 0.70, 1.0);
uniform vec4 color_foam     : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_horizon_fresnel : source_color = vec4(0.55, 0.78, 0.82, 1.0);

group_uniforms Toon_Shading;
uniform int light_bands : hint_range(2, 6) = 3;
uniform float band_softness : hint_range(0.0, 0.3) = 0.08;
uniform float rim_power : hint_range(0.5, 8.0) = 4.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

group_uniforms Foam;
uniform float foam_jacobian_threshold : hint_range(-1.0, 1.5) = 0.85;
uniform float foam_edge_softness : hint_range(0.01, 1.0) = 0.45;
uniform float foam_threshold_jitter : hint_range(0.0, 1.0) = 0.35;  // makes the wave-crest foam line irregular/wobbly
uniform float foam_noise_scale : hint_range(0.01, 1.0) = 0.15;
uniform float foam_scroll_speed : hint_range(0.0, 2.0) = 0.2;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.5;
uniform float foam_dither_amount : hint_range(0.0, 0.2) = 0.04;
uniform bool use_custom_foam_texture = false;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform float foam_uv_scale : hint_range(0.05, 12.0) = 2.0;
uniform float foam_uv_scale_2 : hint_range(0.05, 12.0) = 2.7;       // second sample's scale - keep different from foam_uv_scale
uniform float foam_warp_amount : hint_range(0.0, 1.0) = 0.35;       // UV distortion strength; raises seam-breaking further
uniform float foam_speed : hint_range(0.0, 2.0) = 0.12;
uniform float foam_crest_threshold : hint_range(0.0, 1.0) = 0.5;    // ripple-ring foam threshold (separate from wave-crest foam)
uniform float foam_crest_softness : hint_range(0.01, 1.0) = 0.3;

group_uniforms Sparkle;
uniform float sparkle_intensity : hint_range(0.0, 3.0) = 0.6;
uniform float sparkle_grid_scale : hint_range(1.0, 400.0) = 120.0;
uniform float sparkle_speed : hint_range(0.0, 5.0) = 0.6;
uniform float sparkle_sharpness : hint_range(1.0, 512.0) = 300.0;
uniform float sparkle_rarity : hint_range(0.8, 0.999) = 0.985;

group_uniforms Interaction;
// Pushed every frame by WaterManager.gd - do not rename these.
uniform vec4 ripple_data[16]; // xy = world contact point (x,z), z = spawn time (sim_time), w = strength
uniform int ripple_count : hint_range(0, 16) = 0;
uniform float sim_time = 0.0;
uniform float ripple_lifetime : hint_range(0.5, 30.0) = 6.0;
uniform float ripple_speed : hint_range(0.1, 20.0) = 2.2;
uniform float ripple_wavelength : hint_range(0.05, 5.0) = 0.7;
uniform float ripple_width : hint_range(0.05, 10.0) = 1.2;
uniform float ripple_amplitude : hint_range(0.0, 3.0) = 0.4;

group_uniforms Biomes;
// Pushed every update_interval by WaterBiomeSystem.gd - do not rename these.
uniform vec4 biome_data[8];   // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];   // x = wave height mult, y = wave frequency mult (1/wave_length_mult), z = wave speed mult, w = turbulence
uniform vec4 biome_ripple[8]; // x = ripple speed mult, y = ripple wavelength mult, z = ripple amplitude mult, w = unused
uniform vec4 biome_look[8];   // x = tint strength, y = foam amount mult, z = roughness add, w = unused
uniform vec4 biome_tint[8];   // rgb = tint color, a = unused

group_uniforms Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform bool enable_shore_foam = true;
uniform float shore_foam_distance : hint_range(0.0, 12.0) = 0.6;

varying vec3 v_world_pos;
varying float v_jacobian;
varying float v_extra_height;   // ripple rings + turbulence layer, used for ripple-crest foam separately from wave-fold foam
varying vec4 v_biome_look;      // x = tint strength, y = foam mult, z = roughness add
varying vec3 v_biome_tint;

// ---------------------------------------------------------------------
// Hash / noise helpers
// ---------------------------------------------------------------------
float hash21(vec2 p) {
	p = mod(p, 289.0);              // keep magnitude bounded regardless of world position
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

// Full 4-octave fbm (manually unrolled, no loop) - identical math to the
// original shader. Used anywhere the result feeds vertex displacement,
// since WaterManager.gd's CPU-side height query must match this exactly
// for buoyant objects to sit on the actual rendered surface, and because
// dropping octaves here is what caused the visibly repeating wave pattern.
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

// 2-octave fbm (manually unrolled, no loop) - cheap fallback for FRAGMENT-
// ONLY cosmetics (foam warp UVs, threshold jitter, fallback foam pattern)
// that have no CPU-side equivalent to stay in sync with, and where the
// per-pixel invocation count makes the savings worth it.
float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	v += amp * value_noise(p);
	p *= 2.03;
	amp *= 0.5;
	v += amp * value_noise(p);
	return v;
}

// 3-octave fbm (manually unrolled) - used only where extra detail is
// actually visible (domain warp shape, close-up foam detail).
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
// Gerstner wave accumulation - swell and chop are separate functions
// (rather than one function branching on an is_swell bool) so neither
// path carries a runtime branch. Direction jitter still uses full fbm()
// noise, identical to the original and to WaterManager.gd's CPU port -
// see the PERFORMANCE NOTES at the top for why that's kept at full
// quality instead of a cheaper substitute.
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

void vertex() {
	vec2 pos_xz = VERTEX.xz;
	float t = TIME;
	float wind_rad = radians(wind_direction_deg);
	float sc = 1.0 / max(meters_per_unit, 0.001);

	// -----------------------------------------------------------
	// Blend biome multipliers for this vertex - soft-edged circles
	// in XZ, identical to WaterBiomeSystem.gd / WaterBiome.gd.
	// The i >= biome_count break is a uniform branch (same for every
	// vertex in the draw call) so it's cheap; the low-weight skip that
	// used to be here was a *varying* branch and has been removed -
	// mix() with a near-zero weight is effectively free.
	// -----------------------------------------------------------
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

	// -----------------------------------------------------------
	// Domain warp for the Gerstner swell/chop field - breaks up the
	// periodic/tiled look when large areas of ocean are visible at once.
	// -----------------------------------------------------------
	vec2 warp_seed = pos_xz * domain_warp_scale;
	vec2 warp = vec2(
		fbm(warp_seed + vec2(0.0, t * domain_warp_speed)),
		fbm(warp_seed + vec2(5.2, -t * domain_warp_speed))
	) - 0.5;
	vec2 warped_pos = pos_xz + warp * domain_warp_amount;

	// -----------------------------------------------------------
	// Gerstner wave stack - manually unrolled (was a 6-iteration loop
	// with dynamic const-array indexing). Waves 1-2 are SWELL (long,
	// tall, slow); waves 3-6 are CHOP (short, subtle). chop_mult (from
	// the biome blend) modulates height/wavelength/speed of the CHOP
	// waves fully, and the SWELL waves at 35% strength.
	// -----------------------------------------------------------
	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	float dDx_dx = 0.0;
	float dDx_dz = 0.0;
	float dDz_dx = 0.0;
	float dDz_dz = 0.0;

	// Large-scale patch noise: some regions of ocean are windier/choppier
	// than others, like real wind gusts moving across the surface.
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
	float e = 0.5; // meters, finite-difference epsilon for the layers below

	// -----------------------------------------------------------
	// Turbulence layer: extra chaotic chop for "wild"/storm biomes.
	// Branchless: turb_height already carries a chop_mult.w factor, so
	// this contributes ~0 automatically outside turbulent biomes. The
	// original if(chop_mult.w > 0.01) guard was removed since chop_mult.w
	// varies per-vertex and the branch would diverge across the biome
	// edge; always running it costs a little more where turbulence truly
	// is off, but avoids that divergence where it's patchy.
	// -----------------------------------------------------------
	vec2 turb_freq = vec2(0.03) * max(chop_mult.y, 0.01);
	float turb_wavelength = 1.0 / max(turb_freq.x, 0.0001) / sc; // approx world-space feature size
	float turb_nyquist_fade = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, turb_wavelength);

	vec2 uv_t = warped_pos * sc * turb_freq + vec2(t * 0.6, t * 0.45);
	float hT = fbm(uv_t) - 0.5;
	float hTX = fbm(uv_t + vec2(e * turb_freq.x, 0.0)) - 0.5;
	float hTZ = fbm(uv_t + vec2(0.0, e * turb_freq.y)) - 0.5;
	float turb_height = chop_amplitude * 1.5 * chop_mult.w * turb_nyquist_fade;
	extra_height += hT * turb_height;
	extra_deriv += vec2(hT - hTX, hT - hTZ) * (turb_height / e);

	// -----------------------------------------------------------
	// Object-driven ripples: expanding decaying rings from
	// WaterManager.spawn_ripple() (hulls, splashes, footsteps...).
	// Re-scaled per-biome via ripple_mult. The i >= ripple_count break
	// is a uniform branch (cheap); the per-ripple validity/band checks
	// that used to `continue` were varying (depend on per-vertex
	// distance) and are now branchless multiplicative masks instead.
	// -----------------------------------------------------------
	float local_ripple_speed = ripple_speed * ripple_mult.x;
	float local_ripple_wavelength = max(ripple_wavelength * ripple_mult.y, 0.05);
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
		float band = exp(-pow((dist - wavefront) / max(ripple_width, 0.001), 2.0));

		float decay = strength * (1.0 - clamp(age / ripple_lifetime, 0.0, 1.0));
		float phase = (dist - wavefront) * k_r;
		float amp = ripple_amplitude * ripple_mult.z * decay * band * valid;

		extra_height += sin(phase) * amp;

		vec2 dir_to = to_point / max(dist, 0.0001); // branchless stand-in for the old dist>0 ? normalize : 0 ternary
		float dh = cos(phase) * k_r * amp;
		extra_deriv += dir_to * dh;
	}

	// Fold the noise/ripple perturbation into the Gerstner slope basis -
	// small heightfield derivatives add directly onto the existing slope.
	tangent.y += extra_deriv.x;
	binormal.y += extra_deriv.y;
	offset.y += extra_height;

	VERTEX += offset;
	NORMAL = normalize(cross(binormal, tangent));

	v_jacobian = jacobian;
	v_extra_height = extra_height;
	v_world_pos = VERTEX;
}

void fragment() {
	vec3 wpos = v_world_pos;
	float t = TIME;
	float sc = 1.0 / max(meters_per_unit, 0.001);
	vec4 look = v_biome_look; // x = tint strength, y = foam mult, z = roughness add

	float ndoty = clamp(NORMAL.y, 0.0, 1.0);
	float crest_lift = clamp(1.0 - v_jacobian, 0.0, 1.5);
	float height_factor = clamp(crest_lift * 0.6 + (1.0 - ndoty) * 0.4, 0.0, 1.0);

	vec3 base = mix(color_deep.rgb, color_shallow.rgb, smoothstep(0.05, 0.55, height_factor));
	base = mix(base, color_crest.rgb, smoothstep(0.55, 0.9, height_factor));

	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, view_dir), 0.0, 1.0), rim_power);
	base = mix(base, color_horizon_fresnel.rgb, fresnel * rim_strength);

	// ---- shore / hull foam via depth buffer (boats, beaches, rocks...) ----
	// Left as a uniform branch on purpose: the alternative is an
	// unconditional depth-texture sample + matrix multiply every fragment,
	// which is strictly more expensive when shore foam is disabled.
	float shore_mask = 0.0;
	if (enable_shore_foam) {
		float depth_raw = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_pos.xyz /= view_pos.w;
		float scene_depth = -view_pos.z;
		float water_depth = -VERTEX.z; // VERTEX is view-space here (fragment stage)
		float diff = max(scene_depth - water_depth, 0.0);
		shore_mask = 1.0 - smoothstep(0.0, max(shore_foam_distance, 0.001), diff);
	}
	base = mix(base, color_shallow.rgb, clamp(shore_mask * 1.2, 0.0, 1.0));

	// biome tint (storm grey-green, cold pale blue, etc.)
	base = mix(base, v_biome_tint, clamp(look.x, 0.0, 1.0));

	// ---- wave-crest fold foam (Gerstner wave breaking) ----
	float threshold_noise = (fbm2(wpos.xz * 0.04 + vec2(12.3, -7.1)) - 0.5) * 2.0 * foam_threshold_jitter;
	float fold_amount = (foam_jacobian_threshold + threshold_noise) - v_jacobian;
	float foam_edge = smoothstep(-foam_edge_softness, foam_edge_softness, fold_amount);

	// ---- ripple-ring crest foam (rings from spawn_ripple / turbulence) ----
	float extra_ref = max(ripple_amplitude, 0.001);
	float extra_norm = clamp(v_extra_height / extra_ref, -1.0, 1.0);
	float ripple_crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, extra_norm);

	// max(), not add - a ripple ring crossing a breaking wave shouldn't
	// double up into solid white.
	float fold_mask = max(foam_edge, ripple_crest);

	// ---- foam pattern: custom texture (seam-broken via 2 rotated, warped
	// samples) or procedural fallback ----
	vec2 foam_warp = (vec2(
		fbm2(wpos.xz * sc * 0.02 + vec2(3.3, 8.8)),
		fbm2(wpos.xz * sc * 0.02 + vec2(-4.1, 1.7))
	) - 0.5) * foam_warp_amount;

	float foam_pattern;
	if (use_custom_foam_texture) {
		// Uniform branch (same for the whole draw call) - kept for the
		// same reason as enable_shore_foam above: the alternative always
		// costs a texture sample even when the fallback noise is wanted.
		vec2 uv_a = wpos.xz * sc * foam_uv_scale * 0.1 + vec2(t * foam_speed, 0.0) + foam_warp;
		vec2 uv_b = rotate2(wpos.xz * sc, radians(37.0)) * foam_uv_scale_2 * 0.1 - vec2(0.0, t * foam_speed * 0.8) + foam_warp * 0.6;
		float tex_a = texture(foam_texture, uv_a).r;
		float tex_b = texture(foam_texture, uv_b).r;
		foam_pattern = clamp(tex_a * 0.65 + tex_b * 0.65, 0.0, 1.0);
	} else {
		vec2 fuv = wpos.xz * sc * foam_uv_scale * 0.2 + vec2(t * foam_speed, 0.0) + foam_warp;
		foam_pattern = fbm2(fuv * 3.0);
	}

	vec2 detail_uv = wpos.xz * foam_noise_scale + vec2(t * foam_scroll_speed, t * foam_scroll_speed * 0.7);
	float foam_detail = fbm3(detail_uv + vec2(50.0));
	float foam_mask = fold_mask * mix(0.55, 1.0, foam_detail) * foam_pattern;
	foam_mask *= foam_amount * look.y;

	float dither = (hash21(wpos.xz * 3.7 + TIME) - 0.5) * foam_dither_amount;
	foam_mask = clamp(foam_mask + dither, 0.0, 1.0);

	float total_foam = clamp(foam_mask + shore_mask * look.y, 0.0, 1.0);

	ALBEDO = mix(base, color_foam.rgb, total_foam);
	ROUGHNESS = clamp(mix(0.35, 0.7, total_foam) + look.z, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);

	float bands = float(light_bands);
	float stepped = floor(NdotL * bands) / bands;
	float diffuse = smoothstep(stepped - band_softness, stepped + band_softness, NdotL);
	diffuse = mix(stepped, diffuse, 0.6);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diffuse * ATTENUATION;

	vec3 half_vec = normalize(LIGHT + VIEW);
	float NdotH = clamp(dot(NORMAL, half_vec), 0.0, 1.0);
	float spec = pow(NdotH, sparkle_sharpness);

	vec2 cell = floor(v_world_pos.xz * (sparkle_grid_scale * 0.01) + vec2(TIME * sparkle_speed * 0.15));
	float flicker = hash21(cell + floor(TIME * sparkle_speed * 3.0) * 0.001);
	float glint = step(sparkle_rarity, flicker);

	// Suppress sparkle glints where foam has pushed roughness up - glints
	// showing through solid foam look wrong.
	float foam_suppress = 1.0 - smoothstep(0.45, 0.75, ROUGHNESS);

	SPECULAR_LIGHT += LIGHT_COLOR * spec * glint * sparkle_intensity * ATTENUATION * foam_suppress;
}
