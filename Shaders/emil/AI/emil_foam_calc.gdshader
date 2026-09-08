shader_type canvas_item;

// Derives a foam mask from how much the displacement map compresses
// the surface (wave crests squeeze together -> foam), then masks a
// tiling foam texture with it.

uniform sampler2D displacement_map;
uniform sampler2D sea_foam: repeat_enable;
uniform sampler2D noise;

// Must match "world_scale" on the displacement + water shaders.
uniform float world_scale : hint_range(1.0, 200.0) = 10.0;

// Distance (in world units) between the neighbouring samples used to
// measure crest compression. Bigger = smoother but less precise foam edges.
uniform float sampling_distance_scale : hint_range(1.0, 50.0) = 10.0;

// Jacobian determinant range mapped from "flat water" to "fully
// compressed crest". Narrowing this makes foam appear more suddenly.
uniform float compression_start : hint_range(-2.0, 1.0) = 0.0;
uniform float compression_end : hint_range(-2.0, 1.0) = 0.7;

// The foam texture is sampled at two tiling frequencies: a coarse one
// for calm water and a fine one that kicks in on compressed crests.
uniform float foam_tiling_low : hint_range(1.0, 32.0) = 8.0;
uniform float foam_tiling_high : hint_range(1.0, 64.0) = 24.0;

// Contrast curve applied to the foam texture sample. Push the two
// values closer together for thin, crisp streaks; further apart for
// soft, broad patches.
uniform float foam_contrast_low : hint_range(0.0, 1.0) = 0.5;
uniform float foam_contrast_high : hint_range(0.0, 1.0) = 0.85;

// Breaks up the foam mask with a secondary noise so it doesn't read as
// one uniform sheet of suds.
uniform float noise_threshold_low : hint_range(0.0, 1.0) = 0.2;
uniform float noise_threshold_high : hint_range(0.0, 1.0) = 0.7;

vec3 get_displacement(vec2 uv) {
	return texture(displacement_map, uv).rgb;
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(displacement_map, 0));
	vec2 sampling_distance = texel * sampling_distance_scale;

	vec2 pos = (UV - 0.5) * world_scale;
	vec2 wave_current = pos + get_displacement(UV).xz;
	vec2 wave_r = pos + vec2(sampling_distance.x, 0) + get_displacement(UV + vec2(texel.x, 0)).xz;
	vec2 wave_b = pos + vec2(0, sampling_distance.y) + get_displacement(UV + vec2(0, texel.y)).xz;

	vec2 dpos_x = wave_r - wave_current;
	vec2 dpos_z = wave_b - wave_current;

	float sa = cross(vec3(dpos_x, 0), vec3(dpos_z, 0)).z;

	float jacobian_d = sa / (sampling_distance.x * sampling_distance.y);

	float compression = 1.0 - smoothstep(compression_start, compression_end, jacobian_d);
	float foam_hf = texture(sea_foam, UV * foam_tiling_high).r;
	float foam_lf = texture(sea_foam, UV * foam_tiling_low).r;

	float mixed_foam = mix(foam_lf, foam_hf, compression);
	mixed_foam = smoothstep(foam_contrast_low, foam_contrast_high, mixed_foam);

	float noise_v = texture(noise, UV).r;
	noise_v = smoothstep(noise_threshold_low, noise_threshold_high, noise_v);

	float foam = clamp(compression * mixed_foam * noise_v, 0.0, 1.0);

	COLOR = vec4(vec3(foam), 1.0);
}
