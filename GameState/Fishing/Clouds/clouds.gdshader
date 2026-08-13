shader_type sky;
group_uniforms cloud_data;

uniform sampler2D sky_texture;
uniform float power = 0.2;
uniform float scale_a = 0.2;
uniform float scale_b = 0.5;
group_uniforms speed;
uniform float speed = 0.2;
uniform vec2 speed_a = vec2(0.1);
uniform vec2 speed_b = vec2(0.1);

uniform float density : hint_range(0.0, 2.0) = 0.9;
uniform float grayness : hint_range(0.0, 1.0) = 0.2;
uniform float cloud_light = 1.0;
uniform float cloud_distortion = 0.2;

group_uniforms sky_colour;
uniform vec3 sky_colour_a0 : source_color = vec3(0.5, 0.8, 1.0);
uniform vec3 sky_colour_b0 : source_color = vec3(0.3, 0.5, 1.0);
uniform vec3 sky_colour_a1 : source_color = vec3(0.125, 0.2, 0.25);
uniform vec3 sky_colour_b1 : source_color = vec3(0.075, 0.125, 0.25);

group_uniforms ground_colours;
uniform vec3 ground_colour_a0 : source_color = vec3(1.0, 0.8, 0.5);
uniform vec3 ground_colour_b0 : source_color = vec3(1.0, 0.5, 0.3);
uniform vec3 ground_colour_a1 : source_color = vec3(0.25, 0.2, 0.125);
uniform vec3 ground_colour_b1 : source_color = vec3(0.25, 0.125, 0.075);

group_uniforms sun_data;
uniform vec3 sun_colour_a : source_color = vec3(1.0, 0.98, 0.025);
uniform vec3 sun_colour_b : source_color = vec3(1.0, 0.5, 0.0);
uniform float sun_size = 0.995;
uniform float sun_softness = 0.002;
uniform vec2 sunset_range = vec2(-0.1, 0.3);

float to_grayscale(vec3 colour) {
	return dot(colour, vec3(0.299, 0.587, 0.114));
}

vec3 do_ceil(vec3 eye, vec3 sun) {
	vec3 mix_0 = mix(sky_colour_a0, sky_colour_b0, eye.y);
	vec3 mix_1 = mix(sky_colour_a1, sky_colour_b1, eye.y);
	return mix(mix_1, mix_0, smoothstep(sunset_range.x, sunset_range.y, sun.y));
}

vec3 do_floor(vec3 eye, vec3 sun) {
	vec3 mix_0 = mix(sky_colour_a0, sky_colour_b0, -eye.y);
	vec3 mix_1 = mix(sky_colour_a1, sky_colour_b1, -eye.y);
	return mix(mix_1, mix_0, smoothstep(sunset_range.x, sunset_range.y, sun.y));
}

void sky() {
	float fade = pow(abs(EYEDIR.y), power);
	vec2 uv_a = (EYEDIR.xz / EYEDIR.y) * scale_a + TIME * speed_a * speed;
	vec2 uv_b = (EYEDIR.xz / EYEDIR.y) * scale_b + TIME * speed_b * speed;
	uv_b += texture(sky_texture, uv_a).rg * cloud_distortion;
	vec3 clouds_a = texture(sky_texture, uv_a).rgb * fade;
	vec3 clouds_b = texture(sky_texture, uv_b).rgb * fade;
	vec3 clouds = smoothstep(density, 2.0, clouds_a + clouds_b);
	vec3 sky_back = EYEDIR.y > 0.0 ? do_ceil(EYEDIR, LIGHT0_DIRECTION) : vec3(0.0);
	
	vec3 sky_with_clouds = sky_back + clouds * cloud_light;
	
	float sun_dot = max(0.0, dot(EYEDIR, LIGHT0_DIRECTION));
	float sun = smoothstep(sun_size, sun_size + sun_softness, sun_dot);
	
	COLOR = vec3(0.0);
	COLOR = EYEDIR.y > 0.0 ? mix(sky_with_clouds, vec3(to_grayscale(sky_with_clouds)), grayness) : COLOR;
	COLOR += sun * mix(sun_colour_b, sun_colour_a, smoothstep(sunset_range.x, sunset_range.y, LIGHT0_DIRECTION.y));
	
	COLOR = EYEDIR.y < 0.0 ? do_floor(EYEDIR, LIGHT0_DIRECTION) : COLOR;
}