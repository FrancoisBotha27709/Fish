shader_type canvas_item;
render_mode blend_disabled;
#include "waves.gdshaderinc"

uniform sampler2D prev : filter_nearest, repeat_disable;
uniform vec2 origin;
uniform float win_size = 256.0;
uniform vec2 shift;
uniform vec2 decay = vec2(0.94, 0.98);
uniform float fold_thr = 0.75;
uniform float fold_soft = 0.55;
uniform vec4 hull_a[16];
uniform vec4 hull_b[16];
uniform int hull_n = 0;

void fragment() {
	vec2 p = origin + UV * win_size;
	vec4 cm, rm, lk;
	vec3 tn, o, T, B;
	vec2 wp;
	float jac;
	biomes(p, cm, rm, lk, tn);
	waves(p, cm, wp, o, T, B, jac);
	float fold = smoothstep(-fold_soft, fold_soft, fold_thr - jac);
	float con = 0.0;
	vec2 q = p + o.xz;
	for (int i = 0; i < 16; i++) {
		if (i >= hull_n) break;
		vec4 a = hull_a[i], b = hull_b[i];
		vec2 d = q - a.xy;
		float n = length(vec2(dot(d, b.xy), dot(d, vec2(-b.y, b.x))) / a.zw);
		con = max(con, b.z * (1.0 - smoothstep(1.0, 1.5, n)));
	}
	vec2 pu = UV + shift;
	vec2 pv = (pu.x < 0.0 || pu.y < 0.0 || pu.x > 1.0 || pu.y > 1.0) ? vec2(0.0) : texture(prev, pu).rg;
	COLOR = vec4(max(fold, pv.x * decay.x), max(con, pv.y * decay.y), 0.0, 1.0);
}
