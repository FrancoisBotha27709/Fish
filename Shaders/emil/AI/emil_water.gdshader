shader_type spatial;

// --- Color ---
// Water color close to the surface / at a shallow grazing view.
uniform vec3 shallow_color : source_color = vec3(0.03, 0.28, 0.34);
// Water color in the depths / straight down.
uniform vec3 deep_color : source_color = vec3(0.0, 0.03, 0.07);
// Foam color. Real sea foam is closer to white than to green.
uniform vec3 foam_color : source_color = vec3(0.88, 0.93, 0.93);

// World-space Y range the shallow/deep blend happens over (tie this to
// your camera height / horizon, not literal water depth).
uniform float depth_blend_min = -0.7;
uniform float depth_blend_max = 1.0;

// Vertex-space offset used to take neighbouring displacement samples
// for building the normal. Smaller = sharper normal detail, but can
// get noisy; larger = smoother but blurrier waves.
uniform float sampling_distance : hint_range(0.001, 0.5) = 0.01;

// Must match "world_scale" on the displacement + foam compute shaders.
uniform float world_scale : hint_range(1.0, 200.0) = 10.0;

uniform sampler2D displacement_map: repeat_disable;
uniform sampler2D foam_map: repeat_disable;

// --- Surface response ---
// Open water is glass-smooth; foam is a diffuse mass of bubbles, so it
// needs much higher roughness or it reads as wet plastic/slime.
uniform float water_roughness : hint_range(0.0, 1.0) = 0.04;
uniform float foam_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float water_specular : hint_range(0.0, 1.0) = 0.5;
// Godot's built-in fake-backlight rim. Keep this low — high values are
// what give flat-shaded water its glowing "slime" look.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
// How much the water brightens/whitens at grazing angles (fresnel).
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.4;
uniform float fresnel_power : hint_range(0.1, 8.0) = 4.0;

vec3 get_displacement(vec2 uv) {
	return texture(displacement_map, uv).rgb;
}

void vertex() {
	vec3 pos = VERTEX.xyz;
	VERTEX += get_displacement(pos.xz / world_scale + 0.5);

	vec3 fwd_pos = pos + vec3(0, 0, -1) * sampling_distance;
	vec3 left_pos = pos + vec3(-1, 0, 0) * sampling_distance;

	vec3 wave_fwd = fwd_pos + get_displacement(fwd_pos.xz / world_scale + 0.5);
	vec3 wave_left = left_pos + get_displacement(left_pos.xz / world_scale + 0.5);

	vec3 fwd_vec = wave_fwd - VERTEX;
	vec3 left_vec = wave_left - VERTEX;

	NORMAL = normalize(cross(fwd_vec, left_vec));
}

void fragment() {
	vec4 world_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	float h_blend = smoothstep(depth_blend_min, depth_blend_max, world_pos.y);
	vec3 mixed_color = mix(deep_color, shallow_color, h_blend);

	float foam = texture(foam_map, UV).r;

	// Fresnel term: water gets brighter/more reflective-looking at
	// grazing angles instead of staying one flat color everywhere,
	// which is a big part of what reads as "real water" vs. a colored blob.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	mixed_color = mix(mixed_color, shallow_color * 1.6, fresnel * fresnel_strength);

	ALBEDO = mix(mixed_color, foam_color, foam);
	ROUGHNESS = mix(water_roughness, foam_roughness, foam);
	SPECULAR = water_specular;
	RIM = rim_strength;
}
