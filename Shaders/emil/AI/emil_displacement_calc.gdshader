shader_type canvas_item;

// Bakes a Gerstner-wave displacement map (RGB = XYZ offset) that the
// water and foam shaders both sample. Runs once per frame into a
// SubViewport, not per-pixel on the ocean mesh.

uniform sampler2D noise: repeat_enable;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float noise_intensity_x : hint_range(-0.3, 0.3) = 0.2;
uniform float noise_intensity_z : hint_range(-0.3, 0.3) = 0.2;
// How fast the noise pans underneath the waves. Higher = choppier detail.
uniform float noise_pan_speed : hint_range(0.0, 0.5) = 0.05;

// Size, in world units, of the area this map covers. Must match
// "world_scale" on emil_water.gdshader and emil_foam_calc.gdshader.
uniform float world_scale : hint_range(1.0, 200.0) = 10.0;

// --- Wave 1: primary swell ---
uniform vec2 wave1_direction = vec2(0.0, 1.0);
uniform float wave1_amplitude : hint_range(0.0, 2.0) = 0.4;
uniform float wave1_frequency : hint_range(0.0, 5.0) = 1.0;
uniform float wave1_speed : hint_range(0.0, 5.0) = 1.3;
uniform float wave1_steepness : hint_range(0.0, 1.0) = 0.2;

// --- Wave 2 ---
uniform vec2 wave2_direction = vec2(1.0, 1.0);
uniform float wave2_amplitude : hint_range(0.0, 2.0) = 0.15;
uniform float wave2_frequency : hint_range(0.0, 5.0) = 1.3;
uniform float wave2_speed : hint_range(0.0, 5.0) = 1.6;
uniform float wave2_steepness : hint_range(0.0, 1.0) = 0.12;

// --- Wave 3 ---
uniform vec2 wave3_direction = vec2(0.5, 1.0);
uniform float wave3_amplitude : hint_range(0.0, 2.0) = 0.12;
uniform float wave3_frequency : hint_range(0.0, 5.0) = 2.0;
uniform float wave3_speed : hint_range(0.0, 5.0) = 2.0;
uniform float wave3_steepness : hint_range(0.0, 1.0) = 0.17;

// --- Wave 4: fine ripple ---
uniform vec2 wave4_direction = vec2(-0.4, 1.0);
uniform float wave4_amplitude : hint_range(0.0, 2.0) = 0.01;
uniform float wave4_frequency : hint_range(0.0, 5.0) = 3.0;
uniform float wave4_speed : hint_range(0.0, 5.0) = 3.0;
uniform float wave4_steepness : hint_range(0.0, 1.0) = 0.1;

// --- Wave 5: fine ripple ---
uniform vec2 wave5_direction = vec2(-0.2, 0.7);
uniform float wave5_amplitude : hint_range(0.0, 2.0) = 0.025;
uniform float wave5_frequency : hint_range(0.0, 5.0) = 4.0;
uniform float wave5_speed : hint_range(0.0, 5.0) = 4.0;
uniform float wave5_steepness : hint_range(0.0, 1.0) = 0.08;

vec3 gerstner(vec2 pos, vec2 direction, float amplitude, float frequency, float speed, float steepness) {
	direction = normalize(direction);
	float noise_value = texture(noise, (pos / world_scale + 0.5) * 2.0 + TIME * direction * noise_pan_speed).r;
	float phase = (TIME * speed + dot(direction, pos) * frequency);
	vec3 displacement;

	displacement.y = sin(phase) * amplitude + noise_value * noise_intensity - noise_intensity / 2.0;
	displacement.xz = direction * cos(phase) * steepness;

	displacement.x += noise_value * noise_intensity_x - noise_intensity_x / 2.0;
	displacement.z += noise_value * noise_intensity_z - noise_intensity_z / 2.0;

	return displacement;
}

vec3 wave(vec2 pos) {
	vec3 displacement = gerstner(pos, wave1_direction, wave1_amplitude, wave1_frequency, wave1_speed, wave1_steepness);
	displacement += gerstner(pos, wave2_direction, wave2_amplitude, wave2_frequency, wave2_speed, wave2_steepness);
	displacement += gerstner(pos, wave3_direction, wave3_amplitude, wave3_frequency, wave3_speed, wave3_steepness);
	displacement += gerstner(pos, wave4_direction, wave4_amplitude, wave4_frequency, wave4_speed, wave4_steepness);
	displacement += gerstner(pos, wave5_direction, wave5_amplitude, wave5_frequency, wave5_speed, wave5_steepness);
	return displacement;
}

void fragment() {
	vec2 pos = (UV - 0.5) * world_scale;
	vec3 displacement = wave(pos);
	COLOR = vec4(displacement, 1.0);
}
