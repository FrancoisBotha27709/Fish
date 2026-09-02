shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_opaque, cull_back;

// ============================================================
// FIRE -- stylized "flame lick" draw shader, real 3D teardrop geometry.
// Assign as the GPUParticles3D "Material Override".
// Set draw_pass_1 to a low-poly SphereMesh (e.g. radial_segments=8,
// rings=6) -- the vertex shader sculpts it into a teardrop lick and spins
// it on its own axis, so it reads correctly as a solid shape from every
// camera angle -- no billboard trick needed.
// Pairs with fire_process_3d.gdshader -- reads INSTANCE_CUSTOM:
//   .x = per-particle random 0..TAU (spin/orientation seed)
//   .y = size_factor 0..1 via abs() (ember .. full lick). Sign is only
//        meaningful to the process shader (gating); draw always uses
//        abs() since gated particles are scaled to zero and never visible.
//   .z = wobble/flicker phase 0..TAU
//   .w = life progress 0..1
// ============================================================

// ---- Shape ----
uniform float segment_facets : hint_range(2.0, 20.0) = 8.0; // angular color-band count around the lick
uniform float twist_speed : hint_range(0.0, 20.0) = 3.5;
uniform float taper_strength : hint_range(0.0, 1.0) = 0.75;  // how sharply the tip pulls to a point
uniform float lick_stretch : hint_range(0.3, 3.0) = 1.0;     // taller/shorter licks
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_freq_x : hint_range(0.0, 20.0) = 6.0;
uniform float flicker_freq_z : hint_range(0.0, 20.0) = 5.3;
uniform float flicker_phase_mult : hint_range(0.0, 10.0) = 3.0;
// Stepped-time rate for spin/flicker only (shape/color/fade are unaffected).
// At 60 this matches plain TIME (fully smooth). Lower it (e.g. 30, 12, 8)
// to make the spin and flicker visibly "tick" at a lower frame rate.
uniform float anim_fps : hint_range(1.0, 60.0) = 60.0;

// ---- Lighting ----
uniform vec3 light_dir = vec3(-0.4, 0.6, 0.7);
uniform float shade_dark : hint_range(0.0, 1.5) = 0.65;
uniform float shade_mid : hint_range(0.0, 1.5) = 1.0;
uniform float shade_bright : hint_range(0.0, 2.0) = 1.25;
uniform float facet_shade_min : hint_range(0.0, 1.5) = 0.85;
uniform float facet_shade_max : hint_range(0.5, 2.0) = 1.15;

// ---- Rim / glow ----
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.45); // gold thread rim
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.6;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.4;
uniform float glow_height_falloff : hint_range(0.0, 1.0) = 0.5; // how much the glow dims toward the tip

// ---- Color over life / height (4-stop gradient, fully re-colorable) ----
uniform vec3 color_core : source_color = vec3(1.00, 0.97, 0.75);   // pale core
uniform vec3 color_yellow : source_color = vec3(1.00, 0.80, 0.20);
uniform vec3 color_orange : source_color = vec3(0.97, 0.45, 0.08);
uniform vec3 color_deep : source_color = vec3(0.65, 0.10, 0.02);   // deep red
uniform float stop_core_pos : hint_range(0.0, 1.0) = 0.22;
uniform float stop_yellow_pos : hint_range(0.0, 1.0) = 0.45;
uniform float stop_orange_pos : hint_range(0.0, 1.0) = 0.70;
uniform float color_height_weight : hint_range(0.0, 1.0) = 0.75; // hottest near base, cooling toward tip
uniform float color_life_weight : hint_range(0.0, 1.0) = 0.4;    // and cooling as the particle ages

// ---- Ember (small spark) variance ----
uniform float ember_tint_shift : hint_range(-1.0, 1.0) = 0.15;
uniform float ember_alpha_mult : hint_range(0.0, 2.0) = 0.8;
uniform float ember_glow_mult : hint_range(0.0, 3.0) = 1.6;

// ---- Opacity / fade ----
uniform float fade_in_end : hint_range(0.0, 1.0) = 0.08;
uniform float fade_out_start : hint_range(0.0, 1.0) = 0.8;

varying float v_progress;
varying float v_height01;
varying vec3 v_normal;
varying float v_facet;
varying float v_size_factor;

vec3 fire_color(float t) {
	if (t < stop_core_pos) {
		return mix(color_core, color_yellow, t / max(stop_core_pos, 0.0001));
	} else if (t < stop_yellow_pos) {
		return mix(color_yellow, color_orange, (t - stop_core_pos) / max(stop_yellow_pos - stop_core_pos, 0.0001));
	} else if (t < stop_orange_pos) {
		return mix(color_orange, color_deep, (t - stop_yellow_pos) / max(stop_orange_pos - stop_yellow_pos, 0.0001));
	} else {
		return color_deep;
	}
}

mat3 rotate_y(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

void vertex() {
	v_progress = INSTANCE_CUSTOM.w;
	v_size_factor = abs(INSTANCE_CUSTOM.y);

	// Quantize TIME to a low tick rate for spin + flicker only -- shape
	// taper, color, and fade all stay driven by continuous v_progress, so
	// only the "liveliness" motion looks lower-frame-rate.
	float anim_time = floor(TIME * anim_fps) / max(anim_fps, 0.0001);

	float phase = INSTANCE_CUSTOM.z;
	float spin_dir = INSTANCE_CUSTOM.x > PI ? 1.0 : -1.0;
	// spin the whole lick around its own axis -- real geometry, so this
	// actually rotates in 3D instead of just twisting a flat UV pattern
	float twist = anim_time * twist_speed * spin_dir + phase;
	mat3 spin = rotate_y(twist);
	vec3 pos = spin * VERTEX;
	pos.y *= lick_stretch;

	// lift the sphere so its base sits at the particle's spawn point rather
	// than straddling it, then taper the top toward a point -- turns the
	// ball into a teardrop flame lick
	float radius = 0.5;
	pos.y += radius;
	float h = clamp(pos.y / (radius * 2.0), 0.0, 1.0); // 0 = base, 1 = tip
	float taper = 1.0 - taper_strength * smoothstep(0.15, 1.0, h);
	pos.x *= taper;
	pos.z *= taper;

	// gentle per-lick flicker so the tip wavers instead of holding rigid
	float flick_x = sin(anim_time * flicker_freq_x + phase * flicker_phase_mult) * flicker_amount * h * 0.25;
	float flick_z = cos(anim_time * flicker_freq_z + phase * (flicker_phase_mult * 0.66)) * flicker_amount * h * 0.2;
	pos.x += flick_x;
	pos.z += flick_z;

	VERTEX = pos;
	NORMAL = normalize(spin * NORMAL);

	v_height01 = h;
	v_normal = NORMAL;
	v_facet = floor(atan(VERTEX.z, VERTEX.x) * segment_facets / TAU);
}

void fragment() {
	vec3 n = normalize(v_normal);
	float ndotl = dot(n, normalize(light_dir));

	// cel-shaded facet banding -- each flat "panel" reads as a distinct
	// shard of color, like appliqued fabric rather than a smooth render
	float facet_shade = mix(facet_shade_min, facet_shade_max, mod(v_facet, 2.0));
	float light_band;
	if (ndotl > 0.55) light_band = shade_bright;
	else if (ndotl > 0.05) light_band = shade_mid;
	else light_band = shade_dark;

	// hottest (pale) near the base, cooling toward red at the tip / as the
	// particle ages
	float t = clamp(v_height01 * color_height_weight + v_progress * color_life_weight, 0.0, 1.0);
	vec3 col = fire_color(t) * facet_shade * light_band;

	bool is_ember = v_size_factor < 0.55;
	if (is_ember) {
		col += vec3(ember_tint_shift) * 0.2;
	}

	// warm gold fresnel rim -- the gilded-thread edge
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), rim_power);
	col = mix(col, rim_color, fresnel * rim_strength);

	float life_in = smoothstep(0.0, fade_in_end, v_progress);
	float life_out = 1.0 - smoothstep(fade_out_start, 1.0, v_progress);
	float alpha_mult = is_ember ? ember_alpha_mult : 1.0;
	float glow_mult = is_ember ? ember_glow_mult : 1.0;

	ALBEDO = col;
	EMISSION = col * glow_strength * glow_mult * (1.0 - glow_height_falloff * v_height01);
	ALPHA = life_in * life_out * alpha_mult;
}
