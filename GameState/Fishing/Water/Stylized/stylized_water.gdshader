shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords, diffuse_lambert, specular_schlick_ggx;

const float JITTER_RATE = 0.002; // must match WaterManager.gd

group_uniforms Waves;
uniform float swell_amplitude : hint_range(0.0, 12.0) = 1.2;
uniform float swell_wavelength_scale : hint_range(0.2, 4.0) = 0.5;
uniform float chop_amplitude : hint_range(0.0, 2.0) = 0.6;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0; // unused: wave_time already includes speed
uniform float wave_choppiness : hint_range(0.0, 1.2) = 0.6;
uniform float wind_direction_deg : hint_range(0.0, 360.0) = 30.0;
uniform float wave_direction_jitter : hint_range(0.0, 60.0) = 12.0;
uniform float chop_patchiness : hint_range(0.0, 1.0) = 0.5;

group_uniforms Large_Scale_Variation;
uniform float domain_warp_amount : hint_range(0.0, 100.0) = 15.0;
uniform float domain_warp_scale : hint_range(0.0005, 0.05) = 0.004;
uniform float domain_warp_speed : hint_range(0.0, 0.2) = 0.02;

group_uniforms Scale;
uniform float meters_per_unit : hint_range(0.001, 100.0) = 1.0;
uniform float mesh_vertex_spacing : hint_range(0.05, 20.0) = 1.25; // set to your real spacing (0.5 recommended)

group_uniforms Water_Body;
uniform vec4 absorption_color : source_color = vec4(0.30, 0.60, 0.48, 1.0);
uniform float absorption_distance : hint_range(0.5, 60.0) = 5.0;
uniform vec4 color_scatter : source_color = vec4(0.035, 0.18, 0.16, 1.0);
uniform vec4 color_crest_scatter : source_color = vec4(0.14, 0.40, 0.32, 1.0);
uniform float crest_scatter_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec4 color_variation_tint : source_color = vec4(0.10, 0.20, 0.05, 1.0);
uniform float color_variation_scale : hint_range(0.0005, 0.05) = 0.02;
uniform float color_variation_speed : hint_range(0.0, 0.05) = 0.003;
uniform float color_variation_strength : hint_range(0.0, 1.0) = 0.3;

group_uniforms Surface;
uniform float water_roughness : hint_range(0.0, 0.5) = 0.09;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float far_roughen_start : hint_range(10.0, 2000.0) = 80.0;
uniform float far_roughen_end : hint_range(20.0, 4000.0) = 500.0;

group_uniforms Reflections;
uniform bool enable_reflections = true;
uniform float reflection_strength : hint_range(0.0, 2.0) = 1.0;
uniform float reflection_min : hint_range(0.0, 0.6) = 0.12;
uniform float reflection_blur : hint_range(0.0, 0.3) = 0.05;
uniform float reflection_step : hint_range(0.1, 3.0) = 0.5;

group_uniforms Detail_Normals;
uniform float detail_height : hint_range(0.0, 1.0) = 0.14;
uniform float detail_scale : hint_range(0.05, 4.0) = 1.0;
uniform float detail_speed : hint_range(0.0, 2.0) = 0.25;
uniform float detail_fade_start : hint_range(5.0, 500.0) = 40.0;
uniform float detail_fade_end : hint_range(10.0, 1000.0) = 170.0;
uniform bool use_normal_maps = false;
uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_tile : hint_range(0.2, 30.0) = 3.0;       // metres per tile (layer A)
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float normal_speed : hint_range(0.0, 3.0) = 0.35;      // metres per second
uniform float ripple_bump_boost : hint_range(0.0, 6.0) = 2.5;  // extra bumpiness inside ripple rings

group_uniforms Refraction_And_Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform bool enable_refraction = true;
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.06;
uniform float underwater_blur : hint_range(0.0, 1.0) = 0.15;
uniform float caustics_strength : hint_range(0.0, 4.0) = 1.2;
uniform float caustics_scale : hint_range(0.05, 3.0) = 1.0;    // procedural fallback
uniform float caustics_depth : hint_range(0.5, 20.0) = 4.0;
uniform bool use_caustics_texture = false;
uniform sampler2D caustics_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float caustics_tile : hint_range(0.2, 30.0) = 2.5;     // metres per tile
uniform float caustics_sharpness : hint_range(0.5, 6.0) = 2.0;

group_uniforms Pollution;
uniform float pollution_amount : hint_range(0.0, 1.0) = 0.2;
uniform float pollution_murk : hint_range(0.0, 8.0) = 3.0;
uniform float slick_scale : hint_range(0.0005, 0.1) = 0.03;
uniform float slick_sheen : hint_range(0.0, 1.0) = 0.7;
uniform vec4 scum_color : source_color = vec4(0.22, 0.24, 0.07, 1.0);
uniform float scum_scale : hint_range(0.0005, 0.1) = 0.03;
uniform float scum_strength : hint_range(0.0, 1.0) = 0.6;

group_uniforms Foam;
uniform vec4 color_foam : source_color = vec4(0.88, 0.90, 0.82, 1.0);
uniform float foam_jacobian_threshold : hint_range(-1.0, 1.5) = 0.75;
uniform float foam_edge_softness : hint_range(0.01, 1.0) = 0.4;
uniform float foam_threshold_jitter : hint_range(0.0, 1.0) = 0.5;
uniform float foam_noise_scale : hint_range(0.01, 1.0) = 0.15;
uniform float foam_scroll_speed : hint_range(0.0, 2.0) = 0.2;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.65;
uniform float foam_crispness : hint_range(0.0, 1.0) = 0.75;
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
uniform float shore_foam_distance : hint_range(0.0, 12.0) = 1.5;
uniform float shore_band_speed : hint_range(0.0, 4.0) = 1.2;

group_uniforms Interaction;
uniform float wave_time = 0.0;
uniform vec4 ripple_data[16];
uniform int ripple_count : hint_range(0, 16) = 0;
uniform float sim_time = 0.0;
uniform float ripple_lifetime : hint_range(0.5, 30.0) = 5.0;
uniform float ripple_speed : hint_range(0.1, 20.0) = 4.0;
uniform float ripple_wavelength : hint_range(0.05, 5.0) = 0.5;
uniform float ripple_width : hint_range(0.05, 10.0) = 3.0;
uniform float ripple_amplitude : hint_range(0.0, 3.0) = 0.4;
uniform float ripple_detail_height : hint_range(0.0, 0.3) = 0.02;

group_uniforms Biomes;
uniform vec4 biome_data[8];
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];
uniform vec4 biome_ripple[8];
uniform vec4 biome_look[8];
uniform vec4 biome_tint[8];

varying vec3 v_world_pos;
varying float v_jacobian;
varying float v_extra_height;
varying vec4 v_biome_look;
varying vec3 v_biome_tint;
varying vec3 v_ripple_mult;

// Must match WaterManager.gd::_hash21
float hash21(vec2 p) {
	p = mod(p, 289.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

// 4 octaves: must match WaterManager.gd::_fbm
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * value_noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float fbm2(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 2; i++) { v += a * value_noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float fbm3(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * value_noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

vec2 rotate2(vec2 v, float r) {
	float s = sin(r), c = cos(r);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i), b = hash21(i + vec2(1, 0)), c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y, du * vec2((b - a) + k * u.y, (c - a) + k * u.x));
}

vec3 fbm_d(vec2 p) {
	mat2 R = mat2(vec2(1.6, -1.2), vec2(1.2, 1.6));
	mat2 m = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	float v = 0.0, amp = 0.5;
	vec2 g = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec3 n = noised(m * p + vec2(float(i) * 7.3, float(i) * 3.1));
		v += amp * n.x;
		g += amp * (n.yz * m);
		m = R * m;
		amp *= 0.5;
	}
	return vec3(v - 0.4375, g);
}

float caustic_pattern(vec2 p, float t) {
	float a = 1.0 - abs(value_noise(p * 1.7 + vec2(t * 0.30, t * 0.18)) * 2.0 - 1.0);
	float b = 1.0 - abs(value_noise(rotate2(p, 0.9) * 2.3 + vec2(-t * 0.22, t * 0.27)) * 2.0 - 1.0);
	return pow(a * b, 5.0) * 3.0;
}

// Foam-style breakup for pollution/algae: domain-warped pattern x fine detail, thresholded.
float patch_mask(vec2 p, float thr, float soft, float seed) {
	p += seed * 13.7;
	vec2 w = (vec2(fbm2(p * 0.6), fbm2(p * 0.6 + vec2(5.2, 1.3))) - 0.5) * 0.8;
	float pat = fbm3((p + w) * 3.0);
	float det = fbm3(p * 7.0 + w * 2.0 + 50.0);
	float f = pat * mix(0.5, 1.0, det) * 1.6;
	return smoothstep(thr - soft, thr + soft, f);
}

vec3 scene_view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_texture, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

vec4 trace_reflection(vec3 P, vec3 R, mat4 proj, mat4 inv_proj) {
	float step_len = max(reflection_step, 0.05);
	vec3 ray = P;
	for (int i = 0; i < 24; i++) {
		ray += R * step_len;
		step_len *= 1.15;
		vec4 c = proj * vec4(ray, 1.0);
		if (c.w <= 0.0) break;
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
		vec3 sp = scene_view_pos(uv, inv_proj);
		float diff = (-ray.z) - (-sp.z);
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

float ripple_env(float age) {
	float u = clamp(age / max(ripple_lifetime, 0.001), 0.0, 1.0);
	return smoothstep(0.0, 0.15, age) * (1.0 - u * u * (3.0 - 2.0 * u));
}

// One Gerstner wave. swell=true uses swell rules, false chop rules (mirrors WaterManager.gd).
void gwave(vec2 pos, float t, float wind_rad, vec4 cm, float patch_mult, bool swell,
		float angle_deg, float base_wl, float steep_base, float amp_scale, float spd_base, float seed,
		inout vec3 offset, inout vec3 tangent, inout vec3 binormal, inout vec4 d) {
	float jit = (fbm(vec2(seed, t * JITTER_RATE)) - 0.5) * 2.0 * wave_direction_jitter;
	float ang = radians(angle_deg + jit) + wind_rad;
	vec2 dir = vec2(cos(ang), sin(ang));

	float wl, cat_amp, spd_b;
	if (swell) {
		wl = max(base_wl * swell_wavelength_scale, 0.5);
		cat_amp = swell_amplitude * mix(1.0, cm.x, 0.35);
		spd_b = mix(1.0, cm.z, 0.35);
	} else {
		wl = max(base_wl / max(cm.y, 0.01), 0.5);
		cat_amp = chop_amplitude * patch_mult * cm.x;
		spd_b = cm.z;
	}
	cat_amp *= smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, wl);

	float k = 6.28318530718 / wl;
	float c = sqrt(9.8 / k) * spd_base * spd_b;
	float a = amp_scale * cat_amp;
	float st = steep_base * wave_choppiness;
	float f = k * (dot(dir, pos) - c * t);
	float s = sin(f), co = cos(f);

	offset += vec3(st * a * dir.x * co, a * s, st * a * dir.y * co);
	float wa = k * a;
	tangent += vec3(-dir.x * dir.x * st * wa * s, dir.x * wa * co, -dir.x * dir.y * st * wa * s);
	binormal += vec3(-dir.x * dir.y * st * wa * s, dir.y * wa * co, -dir.y * dir.y * st * wa * s);
	float ks = k * st * a * s;
	d += vec4(-dir.x * dir.x, -dir.x * dir.y, -dir.y * dir.x, -dir.y * dir.y) * ks;
}

void vertex() {
	vec2 pos_xz = VERTEX.xz;
	float t = wave_time;
	float wind_rad = radians(wind_direction_deg);
	float sc = 1.0 / max(meters_per_unit, 0.001);

	vec4 cm = vec4(1.0, 1.0, 1.0, 0.0);
	vec4 rm = vec4(1.0, 1.0, 1.0, 0.0);
	vec4 lm = vec4(0.0, 1.0, 0.0, 0.0);
	vec3 tm = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= biome_count) break;
		float w = 1.0 - smoothstep(biome_data[i].z, biome_data[i].z + max(biome_data[i].w, 0.001), length(pos_xz - biome_data[i].xy));
		cm = mix(cm, biome_chop[i], w);
		rm = mix(rm, biome_ripple[i], w);
		lm = mix(lm, biome_look[i], w);
		tm = mix(tm, biome_tint[i].rgb, w);
	}
	v_biome_look = lm;
	v_biome_tint = tm;
	v_ripple_mult = rm.xyz;

	vec2 ws = pos_xz * domain_warp_scale;
	vec2 warp = vec2(fbm(ws + vec2(0.0, t * domain_warp_speed)), fbm(ws + vec2(5.2, -t * domain_warp_speed))) - 0.5;
	vec2 wp = pos_xz + warp * domain_warp_amount;

	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec4 d = vec4(0.0);

	float cp = fbm(wp * 0.015 + vec2(4.0, 9.0));
	float pm = mix(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, cp);

	gwave(wp, t, wind_rad, cm, pm, true, 0.0, 85.0, 0.8, 1.0, 0.9, 0.0, offset, tangent, binormal, d);
	gwave(wp, t, wind_rad, cm, pm, true, 24.0, 52.0, 0.7, 0.6, 1.05, 17.17, offset, tangent, binormal, d);
	gwave(wp, t, wind_rad, cm, pm, false, 61.0, 22.0, 0.45, 0.32, 1.3, 34.34, offset, tangent, binormal, d);
	gwave(wp, t, wind_rad, cm, pm, false, -37.0, 13.0, 0.35, 0.2, 1.5, 51.51, offset, tangent, binormal, d);
	gwave(wp, t, wind_rad, cm, pm, false, 104.0, 6.0, 0.22, 0.1, 1.9, 68.68, offset, tangent, binormal, d);
	gwave(wp, t, wind_rad, cm, pm, false, -73.0, 3.2, 0.14, 0.05, 2.2, 85.85, offset, tangent, binormal, d);

	float jacobian = (1.0 + d.x) * (1.0 + d.w) - d.y * d.z;

	float extra_h = 0.0;
	vec2 extra_d = vec2(0.0);
	float e = 0.5;
	vec2 tf = vec2(0.03) * max(cm.y, 0.01);
	float tw = 1.0 / max(tf.x, 0.0001) / sc;
	float tfade = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, tw);
	vec2 uvt = wp * sc * tf + vec2(t * 0.6, t * 0.45);
	float hT = fbm(uvt) - 0.5;
	float hTX = fbm(uvt + vec2(e * tf.x, 0.0)) - 0.5;
	float hTZ = fbm(uvt + vec2(0.0, e * tf.y)) - 0.5;
	float th = chop_amplitude * 1.5 * cm.w * tfade;
	extra_h += hT * th;
	extra_d += vec2(hT - hTX, hT - hTZ) * (th / e);

	float rspd = ripple_speed * rm.x;
	float rwl = max(ripple_wavelength * rm.y, mesh_vertex_spacing * 3.5);
	float rwid = max(ripple_width, mesh_vertex_spacing * 2.0);
	float k_r = TAU / rwl;
	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) break;
		float age = sim_time - ripple_data[i].z;
		float valid = step(0.0, age) * step(age, ripple_lifetime) * step(0.0001, ripple_data[i].w);
		vec2 to_p = (pos_xz - ripple_data[i].xy) * sc;
		float dist = length(to_p);
		float front = age * rspd;
		float bx = (dist - front) / (rwid * (1.0 + max(age, 0.0) * 0.25));
		float band = exp(-bx * bx);
		float decay = ripple_data[i].w * ripple_env(age) * inversesqrt(1.0 + max(front, 0.0) * 0.5);
		float phase = (dist - front) * k_r;
		float amp = ripple_amplitude * rm.z * decay * band * valid;
		extra_h += sin(phase) * amp;
		extra_d += (to_p / max(dist, 0.0001)) * (cos(phase) * k_r * amp);
	}

	tangent.y += extra_d.x;
	binormal.y += extra_d.y;
	offset.y += extra_h;
	VERTEX += offset;
	NORMAL = normalize(cross(binormal, tangent));
	v_jacobian = jacobian;
	v_extra_height = extra_h;
	v_world_pos = VERTEX;
}

void fragment() {
	vec3 wpos = v_world_pos;
	float t = wave_time;
	float sc = 1.0 / max(meters_per_unit, 0.001);
	vec4 look = v_biome_look;
	float k_biome = clamp(look.x, 0.0, 1.0);
	float pollution = clamp(pollution_amount + look.w, 0.0, 1.0);
	float cam_dist = length(VERTEX);
	vec3 view_dir = normalize(VIEW);

	// 1. Pollution + algae masks (foam-style breakup)
	float psoft = mix(0.15, 0.03, foam_crispness);
	float pol_on = smoothstep(0.0, 0.12, pollution);
	vec2 drift = vec2(sim_time * 0.004, -sim_time * 0.003);
	float scum = patch_mask(wpos.xz * scum_scale + drift, mix(0.85, 0.5, pollution), psoft, 1.0) * pol_on * scum_strength;
	float slick = patch_mask(wpos.xz * slick_scale - drift * 1.5, mix(0.9, 0.55, pollution), psoft * 3.0, 2.0) * pol_on * (1.0 - scum);
	float algae_k = clamp(color_variation_strength + pollution * 0.4, 0.0, 1.0);
	float algae = patch_mask(wpos.xz * color_variation_scale + vec2(sim_time * color_variation_speed, -sim_time * color_variation_speed * 0.6), 0.6, psoft * 1.5, 3.0) * algae_k;

	// 2. Detail normals (normal maps or procedural) + ripple rings
	vec3 n_geo = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float wind_rad = radians(wind_direction_deg);
	vec2 wind_dir = vec2(cos(wind_rad), sin(wind_rad));
	float dfade = 1.0 - smoothstep(detail_fade_start, max(detail_fade_end, detail_fade_start + 1.0), cam_dist);
	float calm = (1.0 - 0.7 * slick) * (1.0 - 0.85 * scum);

	vec2 slope = vec2(0.0);
	vec2 tex_slope = vec2(0.0);
	if (use_normal_maps) {
		vec2 w = wpos.xz * sc;
		vec2 sA = texture(normal_map_a, (w + wind_dir * t * normal_speed) / normal_tile).xy * 2.0 - 1.0;
		vec2 sB = texture(normal_map_b, (rotate2(w, 0.9) + vec2(-wind_dir.y, wind_dir.x) * t * normal_speed * 1.3) / (normal_tile * 0.37)).xy * 2.0 - 1.0;
		vec2 sC = texture(normal_map_a, (w * 0.8 + wind_dir * t * normal_speed * 0.5) / (normal_tile * 3.7)).xy * 2.0 - 1.0;
		tex_slope = -(sA + rotate2(sB, -0.9) * 0.7 + sC * 0.5) * normal_strength * dfade * calm;
	} else {
		vec2 uv1 = wpos.xz * sc * detail_scale + wind_dir * t * detail_speed;
		vec2 uv2 = rotate2(wpos.xz * sc, 0.9) * detail_scale * 2.1 + vec2(-wind_dir.y, wind_dir.x) * t * detail_speed * 1.3;
		vec2 uv3 = wpos.xz * sc * detail_scale * 0.22 + wind_dir * t * detail_speed * 0.5;
		vec2 slope1 = fbm_d(uv1).yz * detail_scale * sc;
		vec2 slope2 = rotate2(fbm_d(uv2).yz, -0.9) * detail_scale * sc * 2.1;
		vec2 slope3 = fbm_d(uv3).yz * detail_scale * sc * 0.22;
		float foot = length(fwidth(wpos.xz)) * sc * detail_scale;
		float fade1 = 1.0 - smoothstep(0.06, 0.20, foot);
		float fade2 = 1.0 - smoothstep(0.03, 0.10, foot);
		slope = (slope1 * fade1 + slope2 * 0.5 * fade2 + slope3 * 3.0) * detail_height;
		slope *= dfade * calm;
	}

	float r_speed = ripple_speed * v_ripple_mult.x;
	float r_wl = max(ripple_wavelength * v_ripple_mult.y, 0.05);
	float r_k = TAU / r_wl;
	float r_width = max(ripple_width, mesh_vertex_spacing * 2.0);
	float r_fade = 1.0 - smoothstep(0.15, 0.4, length(fwidth(wpos.xz)) * sc / r_wl);
	vec2 rslope = vec2(0.0);
	float renergy = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) break;
		float r_age = sim_time - ripple_data[i].z;
		if (r_age < 0.0 || r_age > ripple_lifetime) continue;
		vec2 to_p = (wpos.xz - ripple_data[i].xy) * sc;
		float r_dist = length(to_p);
		float r_front = r_age * r_speed;
		float r_bx = (r_dist - r_front) / (r_width * (1.0 + r_age * 0.25));
		float r_amp = ripple_detail_height * v_ripple_mult.z * ripple_data[i].w * ripple_env(r_age) * inversesqrt(1.0 + r_front * 0.5) * exp(-r_bx * r_bx);
		renergy += exp(-r_bx * r_bx) * ripple_env(r_age) * ripple_data[i].w;
		float r_phase = (r_dist - r_front) * r_k;
		rslope += (to_p / max(r_dist, 0.0001)) * (cos(r_phase) * r_k * r_amp * sc);
	}
	slope += rslope * r_fade + tex_slope * (1.0 + clamp(renergy, 0.0, 1.0) * ripple_bump_boost);

	vec3 n_world = normalize(vec3(n_geo.x - slope.x * n_geo.y, n_geo.y, n_geo.z - slope.y * n_geo.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float ndotv = clamp(dot(NORMAL, view_dir), 0.02, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, 5.0);

	// 3. Depth
	float water_z = -VERTEX.z;
	vec3 sp0 = scene_view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick0 = max(-sp0.z - water_z, 0.0);
	vec2 uv_r = SCREEN_UV;
	vec3 sp_r = sp0;
	if (enable_refraction) {
		vec2 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		vec2 off = (NORMAL.xy - up_v) * refraction_strength;
		off *= clamp(thick0 * 0.5, 0.0, 1.0) / (1.0 + cam_dist * 0.02);
		vec2 uv_try = clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998));
		vec3 sp_try = scene_view_pos(uv_try, INV_PROJECTION_MATRIX);
		float ok = step(water_z, -sp_try.z);
		uv_r = mix(SCREEN_UV, uv_try, ok);
		sp_r = mix(sp0, sp_try, ok);
	}
	float thick = max(-sp_r.z - water_z, 0.0);
	float ray_len = min(thick / max(abs(view_dir.z), 0.2), 400.0);

	// 4. Colour
	vec3 trans_col = mix(absorption_color.rgb, clamp(v_biome_tint * 1.5 + 0.06, 0.02, 1.0), k_biome * 0.7);
	float murk = 1.0 + pollution * pollution_murk;
	vec3 T = pow(clamp(trans_col, vec3(0.002), vec3(1.0)), vec3(ray_len * murk / max(absorption_distance, 0.05)));

	vec3 scatter_col = mix(color_scatter.rgb, color_variation_tint.rgb, algae);
	scatter_col = mix(scatter_col, v_biome_tint * 0.55, k_biome);
	float wave_h = wpos.y - NODE_POSITION_WORLD.y;
	float h_ref = max(swell_amplitude * 0.8 + chop_amplitude, 0.15);
	float crest = smoothstep(0.15, 1.0, wave_h / h_ref + clamp(1.0 - v_jacobian, 0.0, 1.0) * 0.5);
	vec3 crest_col = mix(color_crest_scatter.rgb, v_biome_tint * 0.9, k_biome);
	crest_col = mix(crest_col, color_variation_tint.rgb * 1.6, algae * 0.5);
	scatter_col = mix(scatter_col, crest_col, crest * crest_scatter_amount);

	vec3 scene_col = vec3(0.0);
	vec3 body = vec3(1.0);
	if (enable_refraction) {
		float lod = clamp(ray_len * underwater_blur, 0.0, 5.0);
		scene_col = textureLod(screen_texture, uv_r, lod).rgb;
		vec3 s_world = (INV_VIEW_MATRIX * vec4(sp_r, 1.0)).xyz;
		float vdepth = wpos.y - s_world.y;
		float cfade = smoothstep(0.0, 0.3, vdepth) * exp(-max(vdepth, 0.0) / max(caustics_depth, 0.1)) * (1.0 - pollution * 0.6);
		float cpat;
		if (use_caustics_texture) {
			vec2 cw = s_world.xz * sc;
			float ca = texture(caustics_texture, (cw + vec2(t * 0.25, t * 0.15)) / caustics_tile).r;
			float cb = texture(caustics_texture, (rotate2(cw, 0.9) + vec2(-t * 0.2, t * 0.3)) / (caustics_tile * 0.73)).r;
			cpat = pow(min(ca, cb), caustics_sharpness) * 4.0;
		} else {
			cpat = caustic_pattern(s_world.xz * sc * caustics_scale, t);
		}
		scene_col *= 1.0 + cpat * caustics_strength * cfade;
		body = vec3(1.0) - T;
	}
	vec3 albedo = scatter_col * body;
	vec3 emit = scene_col * T * (1.0 - fresnel);
	emit = mix(emit, emit * color_variation_tint.rgb * 3.0, algae * 0.5);
	float metallic = 0.0;
	float rough = water_roughness;

	// 5. Foam
	float thr_noise = (fbm2(wpos.xz * 0.04 + vec2(12.3, -7.1)) - 0.5) * 2.0 * foam_threshold_jitter;
	float foam_edge = smoothstep(-foam_edge_softness, foam_edge_softness, (foam_jacobian_threshold + thr_noise) - v_jacobian);
	float extra_norm = clamp(v_extra_height / max(ripple_amplitude, 0.001), -1.0, 1.0);
	float ripple_crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, extra_norm);
	float fold_mask = max(foam_edge, ripple_crest);

	vec2 foam_warp = (vec2(fbm2(wpos.xz * sc * 0.02 + vec2(3.3, 8.8)), fbm2(wpos.xz * sc * 0.02 + vec2(-4.1, 1.7))) - 0.5) * foam_warp_amount;
	float foam_pattern;
	if (use_custom_foam_texture) {
		vec2 ua = wpos.xz * sc * foam_uv_scale * 0.1 + vec2(t * foam_speed, 0.0) + foam_warp;
		vec2 ub = rotate2(wpos.xz * sc, radians(37.0)) * foam_uv_scale_2 * 0.1 - vec2(0.0, t * foam_speed * 0.8) + foam_warp * 0.6;
		foam_pattern = clamp(texture(foam_texture, ua).r * 0.65 + texture(foam_texture, ub).r * 0.65, 0.0, 1.0);
	} else {
		foam_pattern = fbm3((wpos.xz * sc * foam_uv_scale * 0.2 + vec2(t * foam_speed, 0.0) + foam_warp) * 3.0);
	}
	float foam_detail = fbm3(wpos.xz * foam_noise_scale + vec2(t * foam_scroll_speed, t * foam_scroll_speed * 0.7) + vec2(50.0));
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

	// 6. Composite: oil -> scum -> foam
	float sheen = slick * slick_sheen;
	float film_phase = fbm2(wpos.xz * slick_scale * 3.0 + vec2(17.0, 5.0)) * 2.2 + (1.0 - ndotv) * 1.4 + t * 0.02;
	vec3 film = 0.5 + 0.5 * cos(TAU * (vec3(film_phase) + vec3(0.0, 0.33, 0.67)));
	film = mix(vec3(0.5), film, 0.65) * mix(0.45, 1.0, 1.0 - ndotv);
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

	// 7. Reflections
	float refl_w = 0.0;
	if (enable_reflections) {
		vec3 R = reflect(-view_dir, NORMAL);
		vec3 Rw = (INV_VIEW_MATRIX * vec4(R, 0.0)).xyz;
		if (Rw.y > 0.02) {
			vec4 rf = trace_reflection(VERTEX, R, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
			float rfac = clamp(reflection_min + (1.0 - reflection_min) * pow(1.0 - ndotv, 3.0), 0.0, 1.0) * reflection_strength;
			refl_w = clamp(rfac, 0.0, 1.0) * rf.a * smoothstep(0.02, 0.15, Rw.y) * (1.0 - foam) * (1.0 - scum * 0.85);
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