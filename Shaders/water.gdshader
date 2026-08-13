shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Assign this to a ShaderMaterial on a MeshInstance3D using a PlaneMesh with
// plenty of subdivisions (e.g. 100x100) -- the waves are done by displacing
// vertices, so a low-poly plane will look faceted / blocky.
// NOTE: assumes the water MeshInstance3D has no rotation and scale (1,1,1).
// If you need a bigger ocean, make the PlaneMesh itself bigger (its Size
// property) rather than scaling the node -- scaling the node scales the
// wave math unevenly and re-introduces the "oil" look this file fixed.
// If you scale/rotate it anyway, divide `offset` by the scale before adding
// to VERTEX.

// Tuned for a World of Warships-style stylized ocean: smooth rounded
// swells rather than choppy detail, a saturated turquoise-to-navy
// gradient, fairly opaque (you're not meant to see far beneath it), and
// scattered sun-glitter sparkle on the crests.
uniform vec4 shallow_color : source_color = vec4(0.12, 0.62, 0.64, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.14, 0.30, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.1;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.05;

// --- Transparency / underwater fog ---
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform vec4 fog_color : source_color = vec4(0.05, 0.22, 0.28, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.12; // higher = murkier / opaque faster with depth
uniform float alpha_base : hint_range(0.0, 1.0) = 0.95;  // WoWS-style water is quite opaque, not see-through

// --- Fresnel ---
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.6;
uniform float fresnel_power : hint_range(1.0, 8.0) = 5.0;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.15;

// --- Sun glitter (new) -------------------------------------------------
// The single biggest visual ingredient that was missing for a WoWS look:
// small twinkling highlights where the surface happens to reflect the sun
// straight at the camera. Classic ocean-glitter trick: compare the view
// reflection vector to the sun direction, raise to a high power so only
// near-perfect alignment lights up, then mask with cell noise so only a
// scattered subset of matching cells actually sparkle at once (they drift
// and twinkle as the surface animates instead of glowing as one smooth
// blob).
uniform vec3 sun_direction = vec3(0.35, 0.8, 0.25); // direction TOWARD the sun; WaterSurface can sync this from a DirectionalLight3D
uniform vec4 sun_glitter_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform float glitter_strength : hint_range(0.0, 3.0) = 1.0;
uniform float glitter_power : hint_range(8.0, 200.0) = 60.0;
uniform float glitter_scale = 45.0;
uniform float glitter_density : hint_range(0.0, 1.0) = 0.15; // fraction of cells that can sparkle at any moment

// --- Ocean waves (sum of 6 Gerstner waves) ---
// wave_k* / wave_c* are precomputed CPU-side (WaterSurface._build_wave_cache)
// as k = TAU / wavelength and c = sqrt(g * k). Previously this shader
// recomputed both a division AND a sqrt() per wave, per vertex, every frame
// - pure redundant work since these never change unless the exported wave
// params change. Now the vertex shader just reads them.
uniform float wave_speed = 1.0;
uniform float wave_A = 0.8;
uniform float wave_A2 = 0.55;
uniform float wave_A3 = 0.35;
uniform float wave_A4 = 0.22;
uniform float wave_A5 = 0.12;
uniform float wave_A6 = 0.07;
uniform vec2 wave_dir1 = vec2(1.0, 0.3);
uniform vec2 wave_dir2 = vec2(-0.6, 0.8);
uniform vec2 wave_dir3 = vec2(0.2, -1.0);
uniform vec2 wave_dir4 = vec2(-1.0, -0.2);
uniform vec2 wave_dir5 = vec2(0.8, 0.6);
uniform vec2 wave_dir6 = vec2(-0.3, 1.0);
uniform float wave_k1 = 0.140;   // ~ TAU / 45
uniform float wave_k2 = 0.209;   // ~ TAU / 30
uniform float wave_k3 = 0.314;   // ~ TAU / 20
uniform float wave_k4 = 0.449;   // ~ TAU / 14
uniform float wave_k5 = 0.698;   // ~ TAU / 9
uniform float wave_k6 = 1.047;   // ~ TAU / 6
uniform float wave_c1 = 1.17;
uniform float wave_c2 = 1.43;
uniform float wave_c3 = 1.75;
uniform float wave_c4 = 2.10;
uniform float wave_c5 = 2.62;
uniform float wave_c6 = 3.20;
// Lowered from 0.5 -> 0.4: WoWS-style water has rounded, rolling crests
// rather than sharp Gerstner peaks. Steepness controls how "pointy" the
// wave crest gets; lower = smoother, more cartoon-swell silhouette.
uniform float steepness : hint_range(0.0, 1.0) = 0.4;

// --- Boat wake (V-shaped ridge trailing behind the boat) ---
uniform vec3 boat_position = vec3(0.0);
uniform vec3 boat_forward = vec3(0.0, 0.0, 1.0);
uniform float boat_speed = 0.0;
uniform float wake_width = 3.0;
uniform float wake_length = 15.0;
uniform float wake_strength = 0.3;

// --- Ripples: splashes, casts, fish jumping, etc ---
#define MAX_RIPPLES 8
uniform vec4 ripples[MAX_RIPPLES]; // xy = world xz pos, z = strength, w = spawn_time (<=0 = inactive)
uniform float ripple_speed = 3.0;
uniform float ripple_lifetime = 3.0;
uniform float time_now = 0.0;

// --- Procedural noise, purely to break up the "tiled" look of the math waves ---
uniform float detail_noise_scale = 0.6;
uniform float detail_noise_speed = 0.15;
uniform float detail_noise_amplitude = 0.05;
// Lowered from 0.35 -> 0.18: this was making the surface look noisy/choppy
// at the normal level even where the underlying wave shape is calm and
// smooth, which fights the "big rolling swell" look. Keep some -- fully
// zero reads as an unnaturally glassy plastic sheet -- but much less.
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.18;

varying float wave_height;
varying vec2 world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Reduced from 4 octaves to 2 for the per-vertex speed-variation call (see
// gerstner_wave below) since that one only needs a cheap wobble, not fine
// detail -- this alone roughly halves the noise cost of the vertex stage,
// which matters because it used to run 6x per vertex (once per wave).
float fbm2(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 2; i++) {
		total += value_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

// Full 4-octave version, kept for fragment-stage detail where the extra
// resolution is actually visible (foam breakup, normal detail).
float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

// dir is expected pre-normalized (done CPU-side); k = TAU/wavelength and
// c = sqrt(g*k) are also precomputed CPU-side, so this function only does
// the per-vertex-dependent work (dot product, fbm-based speed variation,
// sin/cos) instead of redoing a division + sqrt for every vertex.
//
// Horizontal displacement magnitude is scaled by the wave's own amplitude
// (steep * amplitude) rather than by wavelength alone (steep / k) -- the
// latter shoves long, low waves sideways far more than they rise, folding
// crests over each other in XZ space, which is what read as "oil" before.
vec3 gerstner_wave(vec2 dir, float k, float c, float amplitude, float steep, vec3 pos, float t, inout vec3 tangent, inout vec3 binormal) {
	float speed_variation = 0.8 + fbm2(pos.xz * 0.01) * 0.4;

	float f = k * (
	    dot(dir, pos.xz)
	    - c * t * 0.1 * wave_speed * speed_variation
	);
	float s = sin(f);
	float co = cos(f);
	float a = steep * amplitude;

	tangent += vec3(
		-dir.x * dir.x * steep * s,
		dir.x * steep * co,
		-dir.x * dir.y * steep * s
	);
	binormal += vec3(
		-dir.x * dir.y * steep * s,
		dir.y * steep * co,
		-dir.y * dir.y * steep * s
	);

	return vec3(
		dir.x * a * co,
		amplitude * s,
		dir.y * a * co
	);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Large-scale distortion so waves don't line up into a grid. Kept
	// gentle relative to the noise cell size so it doesn't pinch/fold the
	// wave field on its own.
	vec2 warp;
	warp.x = fbm(world.xz * 0.008 + vec2(13.7, 4.1));
	warp.y = fbm(world.xz * 0.008 + vec2(91.3, 27.6));

	world.xz += (warp - 0.5) * 10.0;

	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 offset = vec3(0.0);

	offset += gerstner_wave(wave_dir1, wave_k1, wave_c1, wave_A,  steepness, world, TIME, tangent, binormal);
	offset += gerstner_wave(wave_dir2, wave_k2, wave_c2, wave_A2, steepness, world, TIME, tangent, binormal);
	offset += gerstner_wave(wave_dir3, wave_k3, wave_c3, wave_A3, steepness, world, TIME, tangent, binormal);
	offset += gerstner_wave(wave_dir4, wave_k4, wave_c4, wave_A4, steepness, world, TIME, tangent, binormal);
	offset += gerstner_wave(wave_dir5, wave_k5, wave_c5, wave_A5, steepness, world, TIME, tangent, binormal);
	offset += gerstner_wave(wave_dir6, wave_k6, wave_c6, wave_A6, steepness, world, TIME, tangent, binormal);

	// Small organic noise on top of the math waves so the repeating Gerstner
	// pattern doesn't read as an obviously tiled grid.
	float n = fbm(world.xz * detail_noise_scale + TIME * detail_noise_speed) - 0.5;
	offset.y += n * detail_noise_amplitude;

	// Boat wake: two trailing ridges that fade out behind + to the sides of the boat.
	vec2 fwd2 = normalize(boat_forward.xz);
	vec2 right2 = vec2(-fwd2.y, fwd2.x);
	vec2 to_vertex = world.xz - boat_position.xz;

	float along = dot(to_vertex, fwd2);
	float across = dot(to_vertex, right2);
	float behind = -along;

	if (behind > 0.0 && behind < wake_length) {
		float lateral_falloff = exp(-pow(across / wake_width, 2.0));
		float ridge = sin(behind * 1.2 - TIME * 4.0) * exp(-behind / wake_length);
		float speed_factor = clamp(boat_speed / 10.0, 0.0, 1.0);
		offset.y += ridge * wake_strength * lateral_falloff * speed_factor;
	}

	// Ripple rings (expanding circles that fade with age)
	for (int i = 0; i < MAX_RIPPLES; i++) {
		float spawn_time = ripples[i].w;
		if (spawn_time <= 0.0) {
			continue;
		}
		float age = time_now - spawn_time;
		if (age < 0.0 || age > ripple_lifetime) {
			continue;
		}
		vec2 rp = ripples[i].xy;
		float dist = distance(world.xz, rp);
		float radius = age * ripple_speed;
		float ring = sin(dist * 3.0 - age * 8.0);
		float envelope = exp(-pow((dist - radius) / 1.5, 2.0));
		float fade = 1.0 - (age / ripple_lifetime);
		offset.y += ring * envelope * fade * 0.15 * ripples[i].z;
	}

	VERTEX += offset;
	wave_height = offset.y;
	world_xz = world.xz;
	NORMAL = normalize(cross(binormal, tangent));
}

void fragment() {
	// Base color from wave height (crest vs trough)
	float height_mix = clamp(wave_height * 2.0 + 0.5, 0.0, 1.0);
	vec3 base_color = mix(deep_color.rgb, shallow_color.rgb, height_mix);

	// Foam on wave crests, broken up by noise so it's not a clean smoothstep ring
	vec2 foam_uv = world_xz;
	foam_uv += (vec2(
	    fbm(world_xz * 0.03),
	    fbm(world_xz * 0.03 + 37.0)
	) - 0.5) * 20.0;

	float foam_noise = fbm(foam_uv * 0.5 + TIME * 0.05);
	float foam = smoothstep(0.15, 0.3, wave_height) * smoothstep(0.3, 0.7, foam_noise);
	base_color = mix(base_color, vec3(1.0), foam * 0.6);

	// Subtle noise-driven normal perturbation, purely cosmetic surface detail
	// so flat-ish areas between waves don't look perfectly smooth/tiled.
	vec2 nuv = world_xz * detail_noise_scale * 3.0 + TIME * detail_noise_speed;
	float n1 = fbm(nuv);
	float n2 = fbm(nuv + vec2(0.1, 0.0));
	float n3 = fbm(nuv + vec2(0.0, 0.1));
	vec3 noise_normal = normalize(vec3((n1 - n2) * 4.0, 1.0, (n1 - n3) * 4.0));
	NORMAL = normalize(mix(NORMAL, noise_normal, detail_normal_strength));

	// Slight albedo variation from the same noise field, again just to avoid
	// large flat patches of identical color.
	base_color *= 1.0 + (fbm(world_xz * 0.15) - 0.5) * 0.15;

	// --- Fresnel -----------------------------------------------------------
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float sparkle = n1; // reuse the noise sample above, no extra fbm call
	float roughness_final = clamp(roughness_amount + (sparkle - 0.5) * sparkle_strength, 0.02, 1.0);

	// --- Sun glitter (new) ---------------------------------------------
	// Where the surface normal happens to reflect the view direction back
	// toward the sun, light up a tight, high-power specular spot. Masking
	// with cell noise (rather than letting every matching pixel glow)
	// gives the scattered "field of tiny sparkles" look instead of one
	// smooth blob of brightness -- much closer to how sun glitter reads on
	// real/stylized ocean water.
	vec3 sun_dir = normalize(sun_direction);
	vec3 view_dir = normalize(VIEW);
	vec3 reflect_dir = reflect(-view_dir, NORMAL);
	float sun_align = clamp(dot(reflect_dir, sun_dir), 0.0, 1.0);
	float glitter_spec = pow(sun_align, glitter_power);

	vec2 glitter_cell = floor(world_xz * glitter_scale + TIME * 1.5);
	float glitter_mask = step(1.0 - glitter_density, hash(glitter_cell));

	float glitter = glitter_spec * glitter_mask;

	// Underwater fog: read how far away whatever is behind this pixel is,
	// and blend toward fog_color / increase opacity the "deeper" the water
	// column looks (works for seafloor, boat hull, docks, etc).
	float fog_amount = 0.0;
	if (fog_density > 0.0001) {
		float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
		vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view.xyz /= view.w;
		float scene_depth = -view.z;
		float pixel_depth = -VERTEX.z;
		float water_column = max(scene_depth - pixel_depth, 0.0);
		fog_amount = 1.0 - exp(-water_column * fog_density);
	}

	vec3 final_color = mix(base_color, fog_color.rgb, fog_amount);

	ALBEDO = final_color;
	ALPHA = mix(mix(alpha_base, 1.0, fog_amount), 1.0, fresnel * fresnel_strength);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_final;
	SPECULAR = mix(0.5, 1.0, fresnel);
	EMISSION = sun_glitter_color.rgb * glitter * glitter_strength;
}
