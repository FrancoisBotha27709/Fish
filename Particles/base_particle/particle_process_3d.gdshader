shader_type particles;

group_uniforms Glow;
uniform float emission_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float spawn_hash_seed = 17.0;                    // vary per-emitter to desync multiple particle nodes
uniform float gating_curve_power : hint_range(0.1, 8.0) = 1.0; // reshapes which slots activate first/last as emission_intensity rises

group_uniforms Emission_Shape;
uniform int emission_shape : hint_enum("Point", "Disc", "Sphere", "Box") = 1;
uniform float emission_radius : hint_range(0.0, 20.0) = 0.25;      // used by Disc, Sphere
uniform vec3 emission_box_extents = vec3(0.5, 0.5, 0.5);           // used by Box (half-extents)

group_uniforms Size;
uniform float size_split_threshold : hint_range(0.0, 1.0) = 0.55;   // must match the draw shader's split point
uniform float small_particle_ratio : hint_range(0.0, 1.0) = 0.4;
uniform float small_scale_mult : hint_range(0.0, 2.0) = 0.35;
uniform float small_lifetime_mult : hint_range(0.05, 4.0) = 0.6;
uniform float small_speed_mult : hint_range(0.0, 8.0) = 1.3;
group_uniforms Movement;
uniform float spin_direction_bias : hint_range(0.0, 1.0) = 0.5;    // fraction of particles spun in the positive direction
uniform vec3 motion_direction = vec3(0.0, 1.0, 0.0);       // the "main flow" axis -- auto-normalized
uniform float motion_speed : hint_range(0.0, 20.0) = 0.8;
uniform float motion_speed_variance : hint_range(0.0, 1.0) = 0.5;
uniform float motion_speed_curve_power : hint_range(0.1, 8.0) = 1.0; // reshapes the speed random distribution

uniform float outward_speed : hint_range(0.0, 20.0) = 0.0;         // radial kick away from the emission point
uniform float outward_speed_variance : hint_range(0.0, 1.0) = 0.0;

uniform float side_drift : hint_range(0.0, 10.0) = 0.7;            // random jitter perpendicular to motion_direction at spawn

uniform float wobble_freq_a : hint_range(0.0, 20.0) = 1.2;         // oscillation frequency, first perpendicular axis
uniform float wobble_freq_b : hint_range(0.0, 20.0) = 1.2;         // oscillation frequency, second perpendicular axis
uniform float wobble_amount_a : hint_range(0.0, 10.0) = 0.2;
uniform float wobble_amount_b : hint_range(0.0, 10.0) = 0.2;
uniform float wobble_phase_offset : hint_range(0.0, 6.2832) = 1.5708; // phase between axis A and axis B (radians)
// Stepped-time rate for wobble/turbulence oscillation only (position
// integration stays continuous). At 60 this is fully smooth; lower it
// to make the motion visibly "update" on a slower tick.
uniform float wobble_fps : hint_range(1.0, 60.0) = 60.0;

uniform float turbulence_strength : hint_range(0.0, 10.0) = 0.0;   // extra chaotic force, independent frequency from wobble
uniform float turbulence_freq : hint_range(0.0, 20.0) = 4.0;

uniform float accel : hint_range(-20.0, 20.0) = 0.15;              // acceleration along motion_direction; negative pulls back
uniform float forward_drag : hint_range(0.0, 10.0) = 0.0;          // drag along motion_direction (sets a terminal speed)
uniform float horizontal_drag : hint_range(0.0, 10.0) = 1.0;       // drag perpendicular to motion_direction
uniform float velocity_inherit_ratio : hint_range(0.0, 1.0) = 0.9;

group_uniforms Lifetime;
uniform float lifetime_min = 1.8;
uniform float lifetime_max = 3.0;
uniform float lifetime_curve_power : hint_range(0.1, 8.0) = 1.0;

group_uniforms Scale;
uniform float start_scale_min = 0.2;
uniform float start_scale_max = 0.35;
uniform float start_scale_curve_power : hint_range(0.1, 8.0) = 1.0;

uniform vec3 end_scale_mult = vec3(2.4, 2.4, 2.4);   // per-axis growth (>1) or shrink (<1) relative to start scale
uniform float scale_curve_power : hint_range(0.1, 8.0) = 1.0; // 1 = linear over life, >1 = slow-then-fast, <1 = fast-then-slow

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 hash21(float p) {
	vec3 p3 = fract(vec3(p, p, p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash31(float p) {
	vec3 p3 = fract(vec3(p, p, p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Orthonormal basis perpendicular to an arbitrary direction, used so
// side_drift/wobble/drag all work relative to motion_direction instead
// of being hardcoded to world X/Z.
void perpendicular_basis(vec3 dir, out vec3 right, out vec3 up2) {
	vec3 arbitrary = (abs(dir.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	right = normalize(cross(arbitrary, dir));
	up2 = cross(dir, right);
}

// Piecewise-linear remap of a uniform [0,1] value so that exactly
// `bias` fraction of the results land above 0.5 -- used to turn a fixed
// 50/50 split into an explicit, tunable ratio.
float biased_split(float x, float bias) {
	float lo = max(1.0 - bias, 0.0001);
	float hi = max(bias, 0.0001);
	if (x < 1.0 - bias) {
		return (x / lo) * 0.5;
	} else {
		return 0.5 + ((x - (1.0 - bias)) / hi) * 0.5;
	}
}

void start() {
	float seed = float(INDEX) + 0.5;

	// Desync this life from the slot's previous lives: without this,
	// `seed` (and everything derived from it) is a pure function of
	// INDEX, so a slot's Nth life is pixel-for-pixel identical to its
	// (N-1)th life. Captured once here at spawn time, so it stays fixed
	// for this particle's whole life.
	float spawn_variation = fract(sin(float(INDEX) * 12.9898 + TIME * 78.233) * 43758.5453123) * 1000.0;
	float jseed = seed + spawn_variation;

	vec2 r = hash21(jseed);
	vec2 r2 = hash21(jseed + 91.7);
	vec2 r3 = hash21(jseed + 173.3);
	vec3 r4 = hash31(jseed + 271.1);
	vec2 r5 = hash21(seed + 337.9);      // NOT jittered -- process() recomputes this every frame from the plain `seed`, so it must stay reproducible across the particle's life (see note above)
	float r6 = hash11(jseed + 419.3);     // independent channel for spin direction
	float r7 = hash11(jseed + 461.7);     // independent channel for outward speed variance

	float activation_threshold = pow(hash11(float(INDEX) + spawn_hash_seed), gating_curve_power);
	bool gated_off = activation_threshold > emission_intensity;

	vec3 local_pos;
	if (emission_shape == 0) {
		// Point
		local_pos = vec3(0.0);
	} else if (emission_shape == 2) {
		// Sphere: point inside a ball
		vec3 dir3 = normalize(r4 - vec3(0.5) + vec3(0.0001));
		float rad = pow(hash11(jseed + 401.0), 1.0 / 3.0) * emission_radius;
		local_pos = dir3 * rad;
	} else if (emission_shape == 3) {
		// Box: uniform point inside the given half-extents
		local_pos = (r4 - vec3(0.5)) * 2.0 * emission_box_extents;
	} else {
		// Disc: flat ring/circle in the emitter's local XZ plane
		float ang = r.x * TAU;
		float rad = sqrt(r.y) * emission_radius;
		local_pos = vec3(cos(ang) * rad, 0.0, sin(ang) * rad);
	}
	vec3 world_pos = (EMISSION_TRANSFORM * vec4(local_pos, 1.0)).xyz;

	bool is_small = r3.x < small_particle_ratio;
	float size_factor = is_small ? mix(0.15, size_split_threshold, r3.y) : mix(size_split_threshold + 0.05, 1.0, r3.y);

	if (gated_off) {
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
		TRANSFORM[2] = vec4(0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);
		VELOCITY = vec3(0.0);
	} else {
		float scale_mult = is_small ? small_scale_mult : 1.0;
		float scale_rand = pow(r5.x, start_scale_curve_power);
		float base_scale = mix(start_scale_min, start_scale_max, scale_rand) * scale_mult;
		TRANSFORM[0] = vec4(base_scale, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, base_scale, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, base_scale, 0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);

		vec3 dir = normalize(motion_direction + vec3(0.0, 0.0001, 0.0));
		vec3 right, up2;
		perpendicular_basis(dir, right, up2);

		float speed_mult = is_small ? small_speed_mult : 1.0;
		float speed_rand = pow(r2.y, motion_speed_curve_power);
		float speed = motion_speed * (1.0 - motion_speed_variance * 0.5 + motion_speed_variance * speed_rand) * speed_mult;

		vec3 main_velocity = dir * speed;
		vec3 side_jitter = (right * (r.x - 0.5) + up2 * (r.y - 0.5)) * side_drift;

		vec3 local_dir = normalize(local_pos + vec3(0.0001));
		float outward = outward_speed * (1.0 - outward_speed_variance * 0.5 + outward_speed_variance * r7);
		vec3 outward_vel = mat3(EMISSION_TRANSFORM) * local_dir * outward;

		VELOCITY = main_velocity + side_jitter + outward_vel + EMITTER_VELOCITY * velocity_inherit_ratio;
	}

	CUSTOM.x = biased_split(r6, spin_direction_bias) * TAU;      // spin-direction split for draw shader
	CUSTOM.y = gated_off ? -(size_factor + 0.001) : size_factor; // sign = gated flag, magnitude = size
	CUSTOM.z = r2.y * TAU;                                       // wobble/spin phase
	CUSTOM.w = 0.0;                                              // life progress 0..1
}

void process() {
	float seed = float(INDEX) + 0.5;
	vec2 r2 = hash21(seed + 91.7);

	bool gated = CUSTOM.y < 0.0;
	float size_factor = abs(CUSTOM.y);
	bool is_small = size_factor < size_split_threshold;

	float lifetime_mult = is_small ? small_lifetime_mult : 1.0;
	float lifetime_rand = pow(r2.x, lifetime_curve_power);
	float lifetime = mix(lifetime_min, lifetime_max, lifetime_rand) * lifetime_mult;

	float progress = clamp(CUSTOM.w + DELTA / lifetime, 0.0, 1.0);
	CUSTOM.w = progress;

	if (!gated) {
		vec3 dir = normalize(motion_direction + vec3(0.0, 0.0001, 0.0));
		vec3 right, up2;
		perpendicular_basis(dir, right, up2);

		float wobble_time = floor(TIME * wobble_fps) / max(wobble_fps, 0.0001);
		float turb_time = wobble_time;

		VELOCITY += dir * accel * DELTA;
		VELOCITY += right * sin(wobble_time * wobble_freq_a + CUSTOM.z) * wobble_amount_a * DELTA;
		VELOCITY += up2 * sin(wobble_time * wobble_freq_b + CUSTOM.z + wobble_phase_offset) * wobble_amount_b * DELTA;

		if (turbulence_strength > 0.0) {
			float tn = sin(turb_time * turbulence_freq + CUSTOM.z * 3.1) * cos(turb_time * turbulence_freq * 0.7 + CUSTOM.x);
			float tn2 = cos(turb_time * turbulence_freq * 1.3 + CUSTOM.z) * sin(turb_time * turbulence_freq * 0.9 + CUSTOM.x * 1.7);
			VELOCITY += (right * tn + up2 * tn2) * turbulence_strength * DELTA;
		}

		// drag: split along motion_direction (forward_drag, sets a
		// terminal falling/rising speed) vs perpendicular to it
		// (horizontal_drag, bleeds off sideways/inherited motion)
		float along = dot(VELOCITY, dir);
		vec3 vel_along = dir * along;
		vec3 vel_perp = VELOCITY - vel_along;
		vel_along -= vel_along * forward_drag * DELTA;
		vel_perp -= vel_perp * horizontal_drag * DELTA;
		VELOCITY = vel_along + vel_perp;

		// TRANSFORM is already world-space (local_coords = false)
		TRANSFORM[3].xyz += VELOCITY * DELTA;

		vec2 r5 = hash21(seed + 337.9);
		float scale_mult = is_small ? small_scale_mult : 1.0;
		float scale_rand = pow(r5.x, start_scale_curve_power);
		float base_scale = mix(start_scale_min, start_scale_max, scale_rand) * scale_mult;
		vec3 scale = vec3(base_scale) * mix(vec3(1.0), end_scale_mult, pow(progress, scale_curve_power));

		TRANSFORM[0] = vec4(scale.x, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, scale.y, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, scale.z, 0.0);
	}
	// gated particles: stay at zero scale/velocity as set in start(), just
	// age silently in place until they naturally die and re-roll the gate.

	ACTIVE = progress < 1.0;
}
