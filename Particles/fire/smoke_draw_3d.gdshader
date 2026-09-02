shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_opaque, cull_back;

// ============================================================
// SMOKE -- stylized "cauliflower puff" draw shader, real 3D geometry.
// Assign as the GPUParticles3D "Material Override".
// Set draw_pass_1 to a low-poly SphereMesh (e.g. radial_segments=8,
// rings=4) so each puff is real geometry that self-shades correctly from
// any camera angle -- no billboard trick needed.
// Pairs with smoke_process_3d.gdshader -- reads INSTANCE_CUSTOM:
//   .x = per-particle random 0..TAU (spin/orientation seed)
//   .y = size_factor 0..1 via abs() (small wisp .. large puff). Sign is
//        only meaningful to the process shader (gating); draw always uses
//        abs() since gated particles are scaled to zero and never visible.
//   .z = wobble/spin phase 0..TAU
//   .w = life progress 0..1
// ============================================================

// ---- Shape ----
uniform float segment_facets : hint_range(2.0, 20.0) = 6.0;
uniform float twist_speed : hint_range(0.0, 20.0) = 1.4;
uniform float bump_amount : hint_range(0.0, 0.5) = 0.18;
uniform float bump_freq : hint_range(0.5, 8.0) = 3.0;      // lumpiness density
uniform float squash_y : hint_range(0.3, 2.0) = 1.0;        // vertical stretch/squash of each puff
// Stepped-time rate for the spin only (shape bumps, color, and fade are
// unaffected). At 60 this matches plain TIME (fully smooth). Lower it
// (e.g. 30, 12, 8) to make the spin visibly "tick" at a lower frame rate.
uniform float anim_fps : hint_range(1.0, 60.0) = 60.0;

// ---- Lighting ----
uniform vec3 light_dir = vec3(-0.4, 0.6, 0.7);
uniform float shade_dark : hint_range(0.0, 1.5) = 0.78;
uniform float shade_mid : hint_range(0.0, 1.5) = 1.0;
uniform float shade_bright : hint_range(0.0, 2.0) = 1.15;
uniform float facet_shade_min : hint_range(0.0, 1.5) = 0.9;
uniform float facet_shade_max : hint_range(0.5, 2.0) = 1.06;

// ---- Rim ----
uniform vec3 rim_color : source_color = vec3(0.95, 0.92, 0.8);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;

// ---- Color over life / height (4-stop gradient, fully re-colorable) ----
uniform vec3 color_stop_0 : source_color = vec3(0.62, 0.62, 0.65); // young / low
uniform vec3 color_stop_1 : source_color = vec3(0.40, 0.40, 0.43); // mid
uniform vec3 color_stop_2 : source_color = vec3(0.18, 0.18, 0.20); // old / high
uniform vec3 color_stop_3 : source_color = vec3(0.05, 0.05, 0.06); // very old / tail smoke
uniform float color_stop_1_pos : hint_range(0.0, 1.0) = 0.4;
uniform float color_stop_2_pos : hint_range(0.0, 1.0) = 0.75;
uniform float color_life_weight : hint_range(0.0, 1.0) = 0.6;    // how much life-progress feeds the gradient
uniform float color_height_weight : hint_range(0.0, 1.0) = 0.25; // how much rise-height feeds the gradient

// ---- Small vs large puff variance ----
uniform float small_puff_tint_shift : hint_range(-1.0, 1.0) = 0.1;
uniform float small_puff_alpha_mult : hint_range(0.0, 2.0) = 0.75;

// ---- Opacity / fade ----
uniform float fade_in_end : hint_range(0.0, 1.0) = 0.12;
uniform float fade_out_start : hint_range(0.0, 1.0) = 0.55;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.85;

varying float v_progress;
varying float v_height01;
varying vec3 v_normal;
varying float v_facet;
varying float v_size_factor;

vec3 smoke_color(float t) {
	if (t < color_stop_1_pos) {
		return mix(color_stop_0, color_stop_1, t / max(color_stop_1_pos, 0.0001));
	} else if (t < color_stop_2_pos) {
		return mix(color_stop_1, color_stop_2, (t - color_stop_1_pos) / max(color_stop_2_pos - color_stop_1_pos, 0.0001));
	} else {
		return mix(color_stop_2, color_stop_3, (t - color_stop_2_pos) / max(1.0 - color_stop_2_pos, 0.0001));
	}
}

mat3 rotate_y(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat3(
		vec3(c, 0.0, -s),
		vec3(0.0, 1.0, 0.0),
		vec3(s, 0.0, c)
	);
}

void vertex() {
	v_progress = INSTANCE_CUSTOM.w;
	v_size_factor = abs(INSTANCE_CUSTOM.y);

	// Quantize TIME to a low tick rate for the spin only -- bump shape,
	// color, and fade all stay driven by continuous v_progress, so only the
	// rotation looks lower-frame-rate.
	float anim_time = floor(TIME * anim_fps) / max(anim_fps, 0.0001);

	float phase = INSTANCE_CUSTOM.z;
	float spin_dir = INSTANCE_CUSTOM.x > PI ? 1.0 : -1.0;
	float twist = anim_time * twist_speed * spin_dir + phase;
	mat3 spin = rotate_y(twist);

	vec3 pos = spin * VERTEX;
	pos.y *= squash_y;

	// lumpy cauliflower-puff bumps, keyed off a fixed direction per vertex
	// so they read as a stable billowing shape rather than crawling noise
	float ang = atan(pos.z, pos.x) * bump_freq + pos.y * 5.0;
	float bump = sin(ang + phase * 4.0) * bump_amount;
	vec3 dir = normalize(pos + vec3(0.0001));
	pos += dir * bump;

	VERTEX = pos;
	NORMAL = normalize(spin * NORMAL);

	v_height01 = clamp(pos.y / 0.5 * 0.5 + 0.5, 0.0, 1.0);
	v_normal = NORMAL;
	v_facet = floor(atan(VERTEX.z, VERTEX.x) * segment_facets / TAU);
}

void fragment() {
	vec3 n = normalize(v_normal);
	float ndotl = dot(n, normalize(light_dir));

	float facet_shade = mix(facet_shade_min, facet_shade_max, mod(v_facet, 2.0));

	float light_band;
	if (ndotl > 0.5) light_band = shade_bright;
	else if (ndotl > 0.0) light_band = shade_mid;
	else light_band = shade_dark;

	// pale/light when young/low, darkening as it ages and rises
	float t = clamp(v_progress * color_life_weight + v_height01 * color_height_weight, 0.0, 1.0);

	vec3 col = smoke_color(t) * facet_shade * light_band;

	bool is_small = v_size_factor < 0.55;
	if (is_small) {
		col += vec3(small_puff_tint_shift) * 0.15;
	}

	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), rim_power);
	col = mix(col, rim_color, fresnel * rim_strength);

	float fade_in = smoothstep(0.0, fade_in_end, v_progress);
	float fade_out = 1.0 - smoothstep(fade_out_start, 1.0, v_progress);
	float size_alpha = is_small ? small_puff_alpha_mult : 1.0;

	ALBEDO = col;
	ALPHA = fade_in * fade_out * max_alpha * size_alpha;
}
