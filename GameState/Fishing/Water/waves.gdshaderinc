uniform float wave_time = 0.0;
uniform vec2 wave_dir[6];
uniform vec4 wave_par[6];
uniform float swell_amplitude : hint_range(0.0, 12.0) = 1.2;
uniform float chop_amplitude : hint_range(0.0, 2.0) = 0.35;
uniform float chop_patchiness : hint_range(0.0, 1.0) = 0.5;
uniform float domain_warp_amount : hint_range(0.0, 100.0) = 35.0;
uniform float domain_warp_scale : hint_range(0.0005, 0.05) = 0.004;
uniform float domain_warp_speed : hint_range(0.0, 0.2) = 0.02;
uniform float meters_per_unit : hint_range(0.001, 100.0) = 1.0;
uniform float mesh_vertex_spacing : hint_range(0.05, 20.0) = 1.25;
uniform vec4 biome_data[8];
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];
uniform vec4 biome_ripple[8];
uniform vec4 biome_look[8];
uniform vec4 biome_tint[8];

float hash21(vec2 p) {
	p = fract(mod(p, 289.0) * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void biomes(vec2 p, out vec4 cm, out vec4 rm, out vec4 lk, out vec3 tn) {
	cm = vec4(1.0, 1.0, 1.0, 0.0);
	rm = cm;
	lk = vec4(0.0, 1.0, 0.0, 0.0);
	tn = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= biome_count) break;
		vec4 d = biome_data[i];
		float w = 1.0 - smoothstep(d.z, d.z + max(d.w, 0.001), length(p - d.xy));
		cm = mix(cm, biome_chop[i], w);
		rm = mix(rm, biome_ripple[i], w);
		lk = mix(lk, biome_look[i], w);
		tn = mix(tn, biome_tint[i].rgb, w);
	}
}

void waves(vec2 p, vec4 cm, out vec2 wp, out vec3 o, out vec3 T, out vec3 B, out float jac) {
	vec2 s = p * domain_warp_scale;
	float tw = wave_time * domain_warp_speed;
	wp = p + (vec2(fbm(s + vec2(0.0, tw)), fbm(s + vec2(5.2, -tw))) - 0.5) * domain_warp_amount;
	float pm = mix(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, fbm(wp * 0.015 + vec2(4.0, 9.0)));
	o = vec3(0.0);
	T = vec3(1.0, 0.0, 0.0);
	B = vec3(0.0, 0.0, 1.0);
	vec3 d = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		vec4 q = wave_par[i];
		vec2 dr = wave_dir[i];
		float wl, a, sp;
		if (i < 2) {
			wl = q.x;
			a = q.z * mix(1.0, cm.x, 0.35);
			sp = mix(1.0, cm.z, 0.35);
		} else {
			wl = max(q.x / max(cm.y, 0.01), 0.5);
			a = q.z * pm * cm.x * smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, wl);
			sp = cm.z;
		}
		float k = TAU / wl;
		float f = k * (dot(dr, wp) - sqrt(9.8 / TAU * wl) * q.y * sp * wave_time);
		float sn = sin(f), cs = cos(f), sa = q.w * a, wa = k * a, ks = k * sa * sn;
		o += vec3(sa * dr.x * cs, a * sn, sa * dr.y * cs);
		T += vec3(-dr.x * dr.x * ks, dr.x * wa * cs, -dr.x * dr.y * ks);
		B += vec3(-dr.x * dr.y * ks, dr.y * wa * cs, -dr.y * dr.y * ks);
		d += vec3(dr.x * dr.x, dr.x * dr.y, dr.y * dr.y) * -ks;
	}
	jac = (1.0 + d.x) * (1.0 + d.z) - d.y * d.y;
}
