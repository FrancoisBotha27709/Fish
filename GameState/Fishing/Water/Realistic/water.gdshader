shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords, diffuse_lambert, specular_schlick_ggx;
#include "res://GameState/Fishing/Water/waves.gdshaderinc"
uniform float wind_direction_deg : hint_range(0.0, 360.0) = 30.0;
group_uniforms Water_Body;
uniform vec3 color_absorption = vec3(1.3, 0.4, 0.6);
uniform float absorption_strength : hint_range(0.0, 4.0) = 1.25;
uniform vec4 color_scatter : source_color = vec4(0.035, 0.18, 0.16, 1.0);
uniform vec4 color_crest_scatter : source_color = vec4(0.14, 0.40, 0.32, 1.0);
uniform float crest_scatter_amount : hint_range(0.0, 1.0) = 0.4;
uniform vec4 color_variation_tint : source_color = vec4(0.10, 0.20, 0.05, 1.0);
uniform float color_variation_scale : hint_range(0.0005, 0.05) = 0.005;
uniform float color_variation_speed : hint_range(0.0, 0.05) = 0.003;
uniform float color_variation_strength : hint_range(0.0, 1.0) = 0.35;
group_uniforms Surface;
uniform float water_roughness : hint_range(0.0, 0.5) = 0.06;
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
uniform float detail_scale : hint_range(0.05, 4.0) = 0.55;
uniform float detail_speed : hint_range(0.0, 2.0) = 0.25;
uniform float detail_fade_start : hint_range(5.0, 500.0) = 40.0;
uniform float detail_fade_end : hint_range(10.0, 1000.0) = 170.0;
group_uniforms Refraction_And_Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform bool enable_refraction = true;
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.06;
uniform float underwater_blur : hint_range(0.0, 1.0) = 0.25;
uniform float caustics_strength : hint_range(0.0, 4.0) = 1.2;
uniform float caustics_scale : hint_range(0.05, 3.0) = 0.6;
uniform float caustics_depth : hint_range(0.5, 20.0) = 4.0;
group_uniforms Pollution;
uniform float pollution_amount : hint_range(0.0, 1.0) = 0.35;
uniform float pollution_murk : hint_range(0.0, 8.0) = 3.0;
uniform float slick_scale : hint_range(0.0005, 0.1) = 0.02;
uniform float slick_sheen : hint_range(0.0, 1.0) = 0.7;
uniform vec4 scum_color : source_color = vec4(0.22, 0.24, 0.07, 1.0);
uniform float scum_scale : hint_range(0.0005, 0.1) = 0.02;
uniform float scum_strength : hint_range(0.0, 1.0) = 0.6;
group_uniforms Foam;
uniform sampler2D foam_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 foam_origin;
uniform float foam_size = 256.0;
uniform vec4 color_foam : source_color = vec4(0.88, 0.90, 0.82, 1.0);
uniform float foam_jacobian_threshold : hint_range(-1.0, 1.5) = 0.75;
uniform float foam_edge_softness : hint_range(0.01, 1.0) = 0.55;
uniform float foam_threshold_jitter : hint_range(0.0, 1.0) = 0.5;
uniform float foam_noise_scale : hint_range(0.01, 1.0) = 0.15;
uniform float foam_scroll_speed : hint_range(0.0, 2.0) = 0.2;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.65;
uniform float foam_crispness : hint_range(0.0, 1.0) = 0.6;
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
uniform float shore_foam_distance : hint_range(0.0, 12.0) = 0.8;
uniform float shore_band_speed : hint_range(0.0, 4.0) = 1.2;
group_uniforms Interaction;
uniform vec4 ripple_data[16];
uniform int ripple_count : hint_range(0, 16) = 0;
uniform float sim_time = 0.0;
uniform float ripple_lifetime : hint_range(0.5, 30.0) = 6.0;
uniform float ripple_speed : hint_range(0.1, 20.0) = 2.2;
uniform float ripple_wavelength : hint_range(0.05, 5.0) = 0.7;
uniform float ripple_width : hint_range(0.05, 10.0) = 1.2;
uniform float ripple_amplitude : hint_range(0.0, 3.0) = 0.4;
uniform float ripple_detail_height : hint_range(0.0, 0.3) = 0.035;
group_uniforms Biomes;
varying vec3 v_world_pos;
varying float v_jacobian;
varying float v_extra_height;
varying vec4 v_biome_look;
varying vec3 v_biome_tint;
varying vec3 v_ripple_mult;
varying vec2 v_rest;
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
vec3 fbm_d(vec2 p) {
	mat2 R = mat2(vec2(1.6, -1.2), vec2(1.2, 1.6));
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
float caustic_pattern(vec2 p, float t) {
	float a = 1.0 - abs(value_noise(p * 1.7 + vec2(t * 0.30, t * 0.18)) * 2.0 - 1.0);
	float b = 1.0 - abs(value_noise(rotate2(p, 0.9) * 2.3 + vec2(-t * 0.22, t * 0.27)) * 2.0 - 1.0);
	return pow(a * b, 5.0) * 3.0;
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
		if (c.w <= 0.0) {
			break;
		}
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
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
	float fade_out = 1.0 - u * u * (3.0 - 2.0 * u);
	return smoothstep(0.0, 0.15, age) * fade_out;
}
void vertex() {
	vec2 p = VERTEX.xz;
	vec4 cm, rm, lk;
	vec3 tn, o, T, B;
	vec2 wp;
	float jac;
	biomes(p, cm, rm, lk, tn);
	v_biome_look = lk;
	v_biome_tint = tn;
	v_ripple_mult = rm.xyz;
	waves(p, cm, wp, o, T, B, jac);
	float sc = 1.0 / max(meters_per_unit, 0.001);
	float eh = 0.0;
	vec2 ed = vec2(0.0);
	if (cm.w > 0.01) {
		float tf = 0.03 * max(cm.y, 0.01);
		float th = chop_amplitude * 1.5 * cm.w * smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, 1.0 / max(tf, 0.0001) / sc);
		vec2 uv = wp * sc * tf + vec2(0.6, 0.45) * wave_time;
		float h = fbm(uv) - 0.5, e = 0.5;
		eh = h * th;
		ed = vec2(h - fbm(uv + vec2(e * tf, 0.0)) + 0.5, h - fbm(uv + vec2(0.0, e * tf)) + 0.5) * (th / e);
	}
	float rs = ripple_speed * rm.x;
	float rk = TAU / max(ripple_wavelength * rm.y, mesh_vertex_spacing * 3.5);
	float rw = max(ripple_width, mesh_vertex_spacing * 2.0);
	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) break;
		vec4 r = ripple_data[i];
		float age = sim_time - r.z;
		vec2 tp = (p - r.xy) * sc;
		float d = length(tp), wf = age * rs;
		float bx = (d - wf) / (rw * (1.0 + max(age, 0.0) * 0.25));
		float amp = ripple_amplitude * rm.z * r.w * ripple_env(age) * inversesqrt(1.0 + max(wf, 0.0) * 0.5) * exp(-bx * bx);
		float ph = (d - wf) * rk;
		eh += sin(ph) * amp;
		ed += tp / max(d, 0.0001) * (cos(ph) * rk * amp);
	}
	T.y += ed.x;
	B.y += ed.y;
	o.y += eh;
	VERTEX += o;
	NORMAL = normalize(cross(B, T));
	v_jacobian = jac;
	v_extra_height = eh;
	v_world_pos = VERTEX;
	v_rest = p;
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
	float pol_on = smoothstep(0.0, 0.12, pollution);
	float scum_n = fbm3(wpos.xz * scum_scale + vec2(t * 0.004, -t * 0.003) + vec2(71.0, 13.0));
	float scum_thr = mix(0.66, 0.42, pollution);
	float scum = smoothstep(scum_thr, scum_thr + 0.04, scum_n) * pol_on * scum_strength;
	float slick_n = fbm3(wpos.xz * slick_scale + vec2(-t * 0.006, t * 0.004));
	float slick_thr = mix(0.68, 0.44, pollution);
	float slick = smoothstep(slick_thr, slick_thr + 0.20, slick_n) * pol_on * (1.0 - scum);
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
	float foot = length(fwidth(wpos.xz)) * sc * detail_scale;
	float fade1 = 1.0 - smoothstep(0.06, 0.20, foot);
	float fade2 = 1.0 - smoothstep(0.03, 0.10, foot);
	vec2 slope = (slope1 * fade1 + slope2 * 0.5 * fade2 + slope3 * 3.0) * detail_height;
	slope *= dfade * (1.0 - 0.7 * slick) * (1.0 - 0.85 * scum);
	float r_speed = ripple_speed * v_ripple_mult.x;
	float r_wl = max(ripple_wavelength * v_ripple_mult.y, 0.05);
	float r_k = TAU / r_wl;
	float r_width = max(ripple_width, mesh_vertex_spacing * 2.0);
	float r_fade = 1.0 - smoothstep(0.15, 0.4, length(fwidth(wpos.xz)) * sc / r_wl);
	vec2 rslope = vec2(0.0);
	for (int i = 0; i < 16; i++) {
		if (i >= ripple_count) {
			break;
		}
		float r_age = sim_time - ripple_data[i].z;
		if (r_age < 0.0 || r_age > ripple_lifetime) {
			continue;
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
	vec3 T = exp(-mix(color_absorption, 2.0 - v_biome_tint * 2.0, k_biome * 0.7) * ray_len * (1.0 + pollution * pollution_murk) * absorption_strength);
	float var_n = fbm2(wpos.xz * color_variation_scale + vec2(t * color_variation_speed, -t * color_variation_speed * 0.6));
	vec3 scatter_col = mix(color_scatter.rgb, color_variation_tint.rgb, smoothstep(0.3, 0.7, var_n) * color_variation_strength);
	scatter_col = mix(scatter_col, v_biome_tint * 0.55, k_biome);
	float wave_h = wpos.y - NODE_POSITION_WORLD.y;
	float h_ref = max(swell_amplitude * 0.8 + chop_amplitude, 0.15);
	float crest = smoothstep(0.15, 1.0, wave_h / h_ref + clamp(1.0 - v_jacobian, 0.0, 1.0) * 0.5);
	vec3 crest_col = mix(color_crest_scatter.rgb, v_biome_tint * 0.9, k_biome);
	scatter_col = mix(scatter_col, crest_col, crest * crest_scatter_amount);
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
	vec3 emit = scene_col * T * (1.0 - fresnel);
	float metallic = 0.0;
	float rough = water_roughness;
	float threshold_noise = (fbm2(wpos.xz * 0.04 + vec2(12.3, -7.1)) - 0.5) * 2.0 * foam_threshold_jitter;
	float fold_amount = (foam_jacobian_threshold + threshold_noise) - v_jacobian;
	float foam_edge = smoothstep(-foam_edge_softness, foam_edge_softness, fold_amount);
	float extra_ref = max(ripple_amplitude, 0.001);
	float extra_norm = clamp(v_extra_height / extra_ref, -1.0, 1.0);
	float ripple_crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, extra_norm);
	vec2 fu = (v_rest - foam_origin) / foam_size;
	vec2 fe = min(fu, 1.0 - fu);
	vec2 fm = texture(foam_map, fu).rg * smoothstep(0.0, 0.04, min(fe.x, fe.y));
	float fold_mask = max(max(foam_edge, ripple_crest), fm.x);
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
	float iw = 0.05 + sin(t * 0.5) * 0.02 + fbm2(wpos.xz * 1.2 + t * 0.03) * 0.08;
	float strip = step(0.001, thick0) * smoothstep(0.0, 0.1 * iw, thick0) * (1.0 - smoothstep(0.8 * iw, iw, thick0)) * look.y;
	float contact = smoothstep(max(foam_thr - foam_soft, 0.01), foam_thr + foam_soft, fm.y * (0.5 + foam_pattern) * look.y + dither);
	float foam = clamp(max(max(foam_waves, shore_foam), max(strip, contact)), 0.0, 1.0);
	float sheen = slick * slick_sheen;
	float film_phase = fbm2(wpos.xz * slick_scale * 3.0 + vec2(17.0, 5.0)) * 2.2 + (1.0 - ndotv) * 1.4 + t * 0.02;
	vec3 film = 0.5 + 0.5 * cos(TAU * (vec3(film_phase) + vec3(0.0, 0.33, 0.67)));
	film = mix(vec3(0.5), film, 0.65);
	film *= mix(0.45, 1.0, 1.0 - ndotv);
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
