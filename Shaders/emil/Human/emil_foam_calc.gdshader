shader_type canvas_item;
uniform sampler2D displacement_map;
uniform sampler2D sea_foam: repeat_enable;
uniform sampler2D noise;

vec3 get_displacement(vec2 uv) {
	return texture(displacement_map, uv).rgb;
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(displacement_map, 0));
	vec2 sampling_distance = texel * 10.0;
	
	vec2 pos = (UV-0.5)*10.0;
	vec2 wave_current = pos + get_displacement(UV).xz;
	vec2 wave_r = pos + vec2(sampling_distance.x, 0) + get_displacement(UV + vec2(texel.x, 0)).xz;
	vec2 wave_b = pos + vec2(0, sampling_distance.y) + get_displacement(UV + vec2(0, texel.y)).xz;
	
	vec2 dpos_x = wave_r - wave_current;
	vec2 dpos_z = wave_b - wave_current;
	
	float sa = cross(vec3(dpos_x, 0), vec3(dpos_z, 0)).z;
	
	float jacobian_d = sa / (sampling_distance.x * sampling_distance.y);
	
	float compression = 1.0 - smoothstep(0.0, 0.7, jacobian_d);
	float foam_hf = texture(sea_foam, UV * 24.0).r;
	float foam_lf = texture(sea_foam, UV * 8.0).r;
	
	float mixed_foam = mix(foam_lf, foam_hf, compression);
	mixed_foam = smoothstep(0.4, 1, mixed_foam);
	
	float noise_v = texture(noise, UV).r;
	noise_v = smoothstep(0.2, 0.7, noise_v);
	noise_v * 8.0;
	
	float foam = clamp(compression * mixed_foam * noise_v, 0, 1);
	
	COLOR = vec4(vec3(foam), 1);
}
