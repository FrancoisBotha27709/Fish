shader_type spatial;
render_mode blend_add, unshaded, depth_draw_opaque, cull_back;

group_uniforms Shape;
uniform float segment_facets : hint_range(2.0, 20.0) = 6.0;
uniform float twist_speed : hint_range(-20.0, 20.0) = 1.4;
uniform vec3 spin_axis = vec3(0.0, 1.0, 0.0);          // arbitrary axis, not locked to Y -- auto-normalized
uniform float bump_amount : hint_range(0.0, 1.0) = 0.18;
uniform float bump_freq : hint_range(0.0, 20.0) = 3.0;       // bump ring density around the spin axis
uniform float bump_vertical_freq : hint_range(0.0, 20.0) = 5.0; // bump density along the spin axis
uniform float bump_phase_mult : hint_range(0.0, 10.0) = 4.0;    // how much per-particle phase offsets the bump pattern
uniform vec3 shape_scale = vec3(1.0, 1.0, 1.0);        // independent stretch/squash on each local axis, post-spin
// Stepped-time rate for the spin only (shape bumps, color, and fade are
// unaffected). At 60 this matches plain TIME (fully smooth). Lower it
// to make the spin visibly tick at a lower frame rate.
uniform float anim_fps : hint_range(1.0, 60.0) = 60.0;

group_uniforms Lighting;
uniform vec3 light_dir = vec3(-0.4, 0.6, 0.7);
uniform float shade_dark : hint_range(0.0, 2.0) = 0.78;
uniform float shade_mid : hint_range(0.0, 2.0) = 1.0;
uniform float shade_bright : hint_range(0.0, 2.0) = 1.15;
uniform float light_threshold_bright : hint_range(-1.0, 1.0) = 0.5;  // N.L above this uses shade_bright
uniform float light_threshold_mid : hint_range(-1.0, 1.0) = 0.0;     // N.L above this (and below bright) uses shade_mid; below both uses shade_dark
uniform float facet_shade_min : hint_range(0.0, 2.0) = 0.9;
uniform float facet_shade_max : hint_range(0.0, 2.0) = 1.06;
uniform float facet_shade_period : hint_range(1.0, 12.0) = 2.0;      // how many facets before the alternating shade repeats

group_uniforms Rim;
uniform vec3 rim_color : source_color = vec3(0.95, 0.92, 0.8);
uniform float rim_power : hint_range(0.1, 16.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;

group_uniforms Glow;
uniform vec3 emission_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 10.0) = 0.0;
uniform float emission_fade_in_end : hint_range(0.0, 1.0) = 0.12;
uniform float emission_fade_out_start : hint_range(0.0, 1.0) = 0.55;
uniform float emission_curve_power : hint_range(0.1, 8.0) = 1.0;

group_uniforms Color_Over_Life;
uniform vec3 color_stop_0 : source_color = vec3(0.62, 0.62, 0.65);
uniform vec3 color_stop_1 : source_color = vec3(0.40, 0.40, 0.43);
uniform vec3 color_stop_2 : source_color = vec3(0.18, 0.18, 0.20);
uniform vec3 color_stop_3 : source_color = vec3(0.05, 0.05, 0.06);
uniform float color_stop_1_pos : hint_range(0.0, 1.0) = 0.4;
uniform float color_stop_2_pos : hint_range(0.0, 1.0) = 0.75;
uniform float color_life_weight : hint_range(0.0, 1.0) = 0.6;        // how much life-progress feeds the gradient
uniform float color_local_up_weight : hint_range(0.0, 1.0) = 0.25;   // how much each particle's own top/bottom feeds it

group_uniforms Size;
uniform float size_split_threshold : hint_range(0.0, 1.0) = 0.55;    // must match the process shader's split point
uniform float small_tint_shift : hint_range(-1.0, 1.0) = 0.1;
uniform float small_alpha_mult : hint_range(0.0, 2.0) = 0.75;

group_uniforms Fade_Over_life;
uniform float fade_in_end : hint_range(0.0, 1.0) = 0.12;
uniform float fade_out_start : hint_range(0.0, 1.0) = 0.55;
uniform float fade_curve_power : hint_range(0.1, 8.0) = 1.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.85;

varying float v_progress;
varying float v_local_up01;
varying vec3 v_normal;
varying float v_facet;
varying float v_size_factor;
varying float v_color_rand;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float gradient_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec3 gradient_color(float t) {
	if (t < color_stop_1_pos) {
		return mix(color_stop_0, color_stop_1, t / max(color_stop_1_pos, 0.0001));
	} else if (t < color_stop_2_pos) {
		return mix(color_stop_1, color_stop_2, (t - color_stop_1_pos) / max(color_stop_2_pos - color_stop_1_pos, 0.0001));
	} else {
		return mix(color_stop_2, color_stop_3, (t - color_stop_2_pos) / max(1.0 - color_stop_2_pos, 0.0001));
	}
}

// Rodrigues' rotation formula -- rotation by angle `a` around arbitrary
// unit axis, generalizing the original's Y-only spin.
mat3 rotate_axis(vec3 axis, float a) {
	axis = normalize(axis + vec3(0.0, 0.0001, 0.0));
	float s = sin(a);
	float c = cos(a);
	float t = 1.0 - c;
	float x = axis.x; float y = axis.y; float z = axis.z;
	return mat3(
		vec3(t*x*x + c,   t*x*y + s*z, t*x*z - s*y),
		vec3(t*x*y - s*z, t*y*y + c,   t*y*z + s*x),
		vec3(t*x*z + s*y, t*y*z - s*x, t*z*z + c)
	);
}

void vertex() {
	v_progress = INSTANCE_CUSTOM.w;
	v_size_factor = abs(INSTANCE_CUSTOM.y);

	// Cheap per-particle random 0..1, derived from two values the
	// process shader already hands us (no new uniforms, no new
	// INSTANCE_CUSTOM channels). Used purely for the fragment-stage
	// color jitter below.
	v_color_rand = gradient_hash11(INSTANCE_CUSTOM.x * 12.9898 + INSTANCE_CUSTOM.z * 78.233);

	float anim_time = floor(TIME * anim_fps) / max(anim_fps, 0.0001);

	float phase = INSTANCE_CUSTOM.z;
	float spin_dir = INSTANCE_CUSTOM.x > PI ? 1.0 : -1.0;
	float twist = anim_time * twist_speed * spin_dir + phase;
	mat3 spin = rotate_axis(spin_axis, twist);

	vec3 pos = spin * VERTEX;
	pos *= shape_scale;

	// bumps keyed off a fixed direction per vertex so they read as a
	// stable shape rather than crawling noise. bump_amount = 0 gives a
	// perfectly smooth particle.
	float ang = atan(pos.z, pos.x) * bump_freq + pos.y * bump_vertical_freq;
	float bump = sin(ang + phase * bump_phase_mult) * bump_amount;
	vec3 dir = normalize(pos + vec3(0.0001));
	pos += dir * bump;

	VERTEX = pos;
	NORMAL = normalize(spin * NORMAL);

	v_local_up01 = clamp(pos.y / 0.5 * 0.5 + 0.5, 0.0, 1.0);
	v_normal = NORMAL;
	v_facet = floor(atan(VERTEX.z, VERTEX.x) * segment_facets / TAU);
}

void fragment() {
	vec3 n = normalize(v_normal);
	float ndotl = dot(n, normalize(light_dir));

	float facet_t = mod(v_facet, facet_shade_period) / max(facet_shade_period - 1.0, 0.0001);
	float facet_shade = mix(facet_shade_min, facet_shade_max, facet_t);

	float light_band;
	if (ndotl > light_threshold_bright) light_band = shade_bright;
	else if (ndotl > light_threshold_mid) light_band = shade_mid;
	else light_band = shade_dark;

	float t = clamp(v_progress * color_life_weight + v_local_up01 * color_local_up_weight, 0.0, 1.0);
	vec3 col = gradient_color(t) * facet_shade * light_band;

	float cr = v_color_rand - 0.5; // -0.5..0.5, stable per particle
	vec3 hsv = rgb2hsv(col);
	hsv.x = fract(hsv.x + cr * 0.12);
	hsv.y = clamp(hsv.y + cr * 0.25, 0.0, 1.0);
	hsv.z = clamp(hsv.z * (1.0 + cr * 0.15), 0.0, 1.0);
	col = hsv2rgb(hsv);

	bool is_small = v_size_factor < size_split_threshold;
	if (is_small) {
		col += vec3(small_tint_shift) * 0.15;
	}

	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), rim_power);
	col = mix(col, rim_color, fresnel * rim_strength);

	float size_alpha = is_small ? small_alpha_mult : 1.0;

	float fade_in = smoothstep(0.0, fade_in_end, v_progress);
	float fade_out = 1.0 - smoothstep(fade_out_start, 1.0, v_progress);
	float alpha_shape = pow(clamp(fade_in * fade_out, 0.0, 1.0), fade_curve_power);

	float e_fade_in = smoothstep(0.0, emission_fade_in_end, v_progress);
	float e_fade_out = 1.0 - smoothstep(emission_fade_out_start, 1.0, v_progress);
	float emission_shape_curve = pow(clamp(e_fade_in * e_fade_out, 0.0, 1.0), emission_curve_power);

	ALBEDO = col;
	ALPHA = alpha_shape * max_alpha * size_alpha;
	EMISSION = emission_color * emission_strength * emission_shape_curve * size_alpha;
}
