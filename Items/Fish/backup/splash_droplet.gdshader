shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// ============================================================================
//  SPLASH DROPLET  -  DRAW shader   (Godot 4.x)
//
//  Use as the material on the GPUParticles3D Draw Pass.
//  Draw Pass mesh: QuadMesh with Size = (1, 1)  (the default).
//  Pair with:  splash_particles.gdshader  as the Process Material.
//
//  Draws two things from the same quad:
//   - droplets: camera-facing, streaked along their velocity, teardrop shaped,
//     with fake-sphere lighting, rim, specular glint and optional refraction.
//   - ripples:  flat rings + a soft foam disc lying on the water surface.
// ============================================================================

// Remove or comment out this line to disable screen refraction. Refraction
// makes droplets look like real lenses but forces a screen copy each frame.
#define USE_REFRACTION

#ifdef USE_REFRACTION
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
#endif

group_uniforms droplet_color;
uniform vec4 core_color : source_color = vec4(0.62, 0.84, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 alt_color : source_color = vec4(0.45, 0.72, 0.95, 1.0);  // mixed in per droplet
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;
uniform float brightness_variation : hint_range(0.0, 1.0) = 0.15;
uniform float brightness = 1.0;  // >1 + glow/bloom = shiny droplets
group_uniforms;

group_uniforms droplet_shape;
uniform float core_opacity : hint_range(0.0, 1.0) = 0.35;   // see-through middle
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.9;    // denser rim
uniform float edge_softness : hint_range(0.01, 1.0) = 0.15;
uniform float edge_blend_power : hint_range(0.1, 8.0) = 2.0;
uniform float teardrop : hint_range(0.0, 1.0) = 0.6;        // 0 = ellipse, 1 = pointed tail
group_uniforms;

group_uniforms droplet_lighting;
uniform vec3 light_direction = vec3(0.4, 0.8, 0.4);   // world space, pointing TO the light
uniform float shade_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_strength : hint_range(0.0, 4.0) = 1.5;
uniform float specular_power : hint_range(2.0, 256.0) = 48.0;
group_uniforms;

#ifdef USE_REFRACTION
group_uniforms droplet_refraction;
uniform float refraction_strength = 0.6;   // negative flips the lens
uniform float refraction_mix : hint_range(0.0, 1.0) = 0.6;
uniform vec4 refraction_tint : source_color = vec4(0.9, 0.97, 1.0, 1.0);
group_uniforms;
#endif

group_uniforms droplet_fade;
uniform float fade_in_time : hint_range(0.0, 1.0) = 0.05;
uniform float fade_out_time : hint_range(0.001, 1.0) = 0.25;
group_uniforms;

group_uniforms ripple;
uniform vec4 ripple_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float ripple_brightness = 1.0;
uniform float ripple_opacity : hint_range(0.0, 1.0) = 0.8;
uniform float landing_ripple_opacity : hint_range(0.0, 1.0) = 0.6;
uniform int ring_count : hint_range(1, 3) = 2;
uniform float ring_radius : hint_range(0.1, 1.0) = 0.8;      // outer ring position (fraction of quad)
uniform float ring_spacing : hint_range(0.02, 0.5) = 0.18;
uniform float ring_thickness : hint_range(0.005, 0.3) = 0.06;
uniform float ring_thin_end : hint_range(0.05, 1.0) = 0.4;   // ring gets this much thinner by the end
uniform float ring_softness : hint_range(0.0, 1.0) = 0.7;
uniform float ring_falloff : hint_range(0.0, 1.0) = 0.55;    // each inner ring is this much fainter
uniform float ring_stagger : hint_range(0.0, 0.5) = 0.1;     // inner rings appear slightly later
uniform float disc_opacity : hint_range(0.0, 1.0) = 0.25;    // foamy disc at the splash spot
uniform float disc_size : hint_range(0.0, 1.0) = 0.5;
uniform float ripple_fade_in : hint_range(0.0, 1.0) = 0.08;
uniform float ripple_fade_out : hint_range(0.001, 1.0) = 0.7;
group_uniforms;

varying vec4 v_custom;
varying vec2 v_axis_view;
varying vec2 v_right_view;
varying vec3 v_light_view;
varying float v_screen_size;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_light_view = normalize((VIEW_MATRIX * vec4(normalize(light_direction), 0.0)).xyz);
	vec3 center = MODEL_MATRIX[3].xyz;

	if (INSTANCE_CUSTOM.x < 0.5) {
		// Droplet: quad's long axis follows velocity, width faces the camera.
		vec3 ax = MODEL_MATRIX[1].xyz;
		float len = length(ax);
		float wid = length(MODEL_MATRIX[0].xyz);
		vec3 axis = len > 0.000001 ? ax / len : vec3(0.0, -1.0, 0.0);

		vec3 to_cam = PROJECTION_MATRIX[3][3] == 0.0
			? normalize(INV_VIEW_MATRIX[3].xyz - center)
			: INV_VIEW_MATRIX[2].xyz;
		vec3 rc = cross(axis, to_cam);
		float rl = length(rc);
		vec3 right = rl > 0.0001 ? rc / rl : INV_VIEW_MATRIX[0].xyz;

		vec3 world_pos = center + right * VERTEX.x * wid + axis * VERTEX.y * len;
		v_axis_view = (VIEW_MATRIX * vec4(axis, 0.0)).xy;
		v_right_view = (VIEW_MATRIX * vec4(right, 0.0)).xy;

		vec4 c = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center, 1.0);
		v_screen_size = wid * abs(PROJECTION_MATRIX[0][0]) / max(abs(c.w), 0.0001) * 0.5;

		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	} else {
		// Ripple: lies flat using the particle transform as-is.
		v_axis_view = vec2(0.0, 1.0);
		v_right_view = vec2(1.0, 0.0);
		v_screen_size = 0.0;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
	}
}

void fragment() {
	float kind = v_custom.x;
	float age = clamp(v_custom.y, 0.0, 1.0);
	float rnd = v_custom.z;

	if (kind < 0.5) {
		// ============================ DROPLET ============================
		float fade = smoothstep(0.0, max(fade_in_time, 0.0001), age)
			* (1.0 - smoothstep(1.0 - fade_out_time, 1.0, age));

		// p.y = +1 is the front (direction of travel), -1 is the tail.
		vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
		float tail = smoothstep(0.0, 1.0, clamp(-p.y, 0.0, 1.0));
		float w = max(1.0 - teardrop * tail, 0.03);
		vec2 q = vec2(p.x / w, p.y);
		float d = length(q);

		float shape = 1.0 - smoothstep(1.0 - edge_softness, 1.0, d);
		if (shape <= 0.001) {
			discard;
		}

		// Fake sphere normal, rotated to match the droplet's on-screen orientation
		float nz = sqrt(max(1.0 - d * d, 0.0));
		vec2 nxy = v_right_view * q.x + v_axis_view * q.y;
		vec3 N = normalize(vec3(nxy, nz) + vec3(0.0, 0.0, 0.0001));

		float edge = pow(1.0 - nz, edge_blend_power);
		vec3 body = mix(core_color.rgb, alt_color.rgb, rnd * color_variation);
		vec3 base = mix(body, edge_color.rgb, edge);

		float ndl = dot(N, v_light_view) * 0.5 + 0.5;
		base *= mix(1.0, 0.5 + ndl, shade_strength);
		base *= 1.0 + (fract(rnd * 7.13) - 0.5) * 2.0 * brightness_variation;

		vec3 H = normalize(v_light_view + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(dot(N, H), 0.0), specular_power) * specular_strength;
		float fres = pow(1.0 - clamp(N.z, 0.0, 1.0), rim_power) * rim_strength;

		float alpha = mix(core_opacity, edge_opacity, edge);

#ifdef USE_REFRACTION
		vec2 off = -N.xy * refraction_strength * v_screen_size * vec2(1.0, VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
		vec3 scene = texture(screen_tex, SCREEN_UV + off).rgb;
		base = mix(base, scene * refraction_tint.rgb, refraction_mix);
		alpha = mix(alpha, 1.0, refraction_mix);
#endif

		vec3 col = base + rim_color.rgb * fres + specular_color.rgb * spec;
		alpha = clamp(alpha + fres * 0.5 + spec, 0.0, 1.0) * shape * fade;

		ALBEDO = col * brightness;
		ALPHA = alpha;
	} else {
		// ============================= RIPPLE ============================
		float fade = smoothstep(0.0, max(ripple_fade_in, 0.0001), age)
			* (1.0 - smoothstep(1.0 - ripple_fade_out, 1.0, age));

		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);

		float thick = max(ring_thickness * mix(1.0, ring_thin_end, age), 0.002);
		float rings = 0.0;
		for (int i = 0; i < 3; i++) {
			if (i >= ring_count) {
				break;
			}
			float fi = float(i);
			float rk = ring_radius - fi * ring_spacing;
			float dist = abs(r - rk);
			float ring = 1.0 - smoothstep(thick * (1.0 - ring_softness), thick, dist);
			float appear = smoothstep(fi * ring_stagger, fi * ring_stagger + 0.15, age);
			rings += ring * pow(ring_falloff, fi) * appear;
		}

		float disc = (1.0 - smoothstep(disc_size * 0.5, disc_size, r)) * disc_opacity * (1.0 - age) * (1.0 - age);
		float edge_guard = 1.0 - smoothstep(0.88, 1.0, r);

		float strength = kind > 1.5 ? landing_ripple_opacity : ripple_opacity;
		float alpha = clamp(rings * strength + disc, 0.0, 1.0) * edge_guard * fade;

		ALBEDO = ripple_color.rgb * ripple_brightness;
		ALPHA = alpha;
	}
}
