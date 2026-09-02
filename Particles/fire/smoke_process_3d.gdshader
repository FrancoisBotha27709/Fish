shader_type particles;
// Drives smoke particle motion in 3D. Assign as the GPUParticles3D
// "Process Material". Pairs with smoke_draw_3d.gdshader.
//
// WORLD-SPACE SIMULATION: written for local_coords = false on the
// GPUParticles3D node, so already-emitted puffs are NOT dragged along when
// the node moves (that's what lets the plume trail behind as the emitter
// moves). Because of that, TRANSFORM here is a WORLD-space transform -- the
// engine does not multiply it by the node's transform for us. So start()
// manually converts the local emission offset into world space using
// EMISSION_TRANSFORM (the node's global transform at the instant this
// particle spawns), and explicitly pulls in EMITTER_VELOCITY to inherit the
// emitter's motion. Also set inherit_velocity_ratio = 1.0 on the
// GPUParticles3D node itself -- that's what tells the engine to actually
// track and populate EMITTER_VELOCITY; velocity_inherit_ratio below then
// controls how much of it each new puff actually keeps.
//
// EMISSION-INTENSITY GATING (replaces changing `amount` / amount_ratio):
// `amount` is a fixed pool sized for the maximum smoke density and must
// never change at runtime -- changing it forces GPUParticles3D to
// reallocate its buffers, causing the exact pop/jitter this architecture
// avoids. Instead, FireSmoke.gd smoothly drives `emission_intensity` (0..1)
// every frame. Each particle slot gets a fixed, INDEX-derived
// `activation_threshold` computed ONCE in start(). If that threshold is
// above the current emission_intensity, the slot still lives out a
// completely normal lifetime cycle (so its natural respawn cadence is
// unaffected) but is parked invisibly (zero scale, zero velocity) instead
// of behaving like a real puff. As emission_intensity rises, more slots
// pass their threshold on their next natural respawn -- staggered across
// the whole pool since slots aren't synchronized -- giving a gradual
// density increase with no pop-in.
//
// This is deliberately decoupled from the ACTIVE = progress < 1.0 lifecycle
// below: gating only ever touches visibility/motion, never the death timer,
// so the two systems can never fight each other. The gate decision is also
// frozen at spawn time (sign-encoded into CUSTOM.y) rather than re-checked
// every frame in process() -- re-checking live would let a particle "pop in"
// mid-life already aged, at a stale spawn position, since EMISSION_TRANSFORM
// is only valid inside start().

// ==================== Emission control ====================
uniform float emission_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float spawn_hash_seed = 17.0; // vary per-emitter to desync multiple smoke nodes

// ==================== Small / large puff mix ====================
uniform float small_particle_ratio : hint_range(0.0, 1.0) = 0.4; // fraction spawning as small wisps
uniform float small_scale_mult : hint_range(0.05, 1.0) = 0.35;
uniform float small_lifetime_mult : hint_range(0.1, 2.0) = 0.6;
uniform float small_rise_speed_mult : hint_range(0.1, 4.0) = 1.3;

// ==================== Emission shape ====================
uniform float emission_radius : hint_range(0.0, 10.0) = 0.25;

// ==================== Motion ====================
uniform float rise_speed : hint_range(0.0, 10.0) = 0.8;
uniform float rise_speed_variance : hint_range(0.0, 1.0) = 0.5;
uniform float side_drift : hint_range(0.0, 5.0) = 0.7;
uniform float wobble_freq : hint_range(0.0, 10.0) = 1.2;
uniform float wobble_amount : hint_range(0.0, 5.0) = 0.2;
// Stepped-time rate for the wobble oscillation only (position integration
// stays continuous). At 60 this is identical to plain TIME (fully smooth).
// Lower it (e.g. 30, 12, 8) to make the wobble visibly "update" on a slower
// tick, like it's animated at a lower frame rate, without touching rise
// speed, lifetime, or anything else.
uniform float wobble_fps : hint_range(1.0, 60.0) = 60.0;
uniform float buoyancy : hint_range(0.0, 5.0) = 0.15;
uniform float horizontal_drag : hint_range(0.0, 10.0) = 1.0; // bleeds off inherited emitter velocity
uniform float velocity_inherit_ratio : hint_range(0.0, 1.0) = 0.9;

// ==================== Lifetime & scale ====================
uniform float lifetime_min = 1.8;
uniform float lifetime_max = 3.0;
uniform float start_scale_min = 0.2;
uniform float start_scale_max = 0.35;
uniform float end_scale_mult = 2.4; // puffs expand with age
uniform float scale_curve_power : hint_range(0.1, 4.0) = 1.0; // 1 = linear growth, >1 = slow-then-fast, <1 = fast-then-slow

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

void start() {
	float seed = float(INDEX) + 0.5;
	vec2 r = hash21(seed);
	vec2 r2 = hash21(seed + 91.7);
	vec2 r3 = hash21(seed + 173.3);

	// Fixed per-slot threshold, compared against the live emission_intensity
	// uniform. Frozen for this particle's whole life via CUSTOM.y's sign.
	float activation_threshold = hash11(float(INDEX) + spawn_hash_seed);
	bool gated_off = activation_threshold > emission_intensity;

	float ang = r.x * TAU;
	float rad = sqrt(r.y) * emission_radius;
	vec3 local_pos = vec3(cos(ang) * rad, 0.0, sin(ang) * rad);
	vec3 world_pos = (EMISSION_TRANSFORM * vec4(local_pos, 1.0)).xyz;

	bool is_small = r3.x < small_particle_ratio;
	// continuous size value: small cluster near the low end, large near the
	// high end, with a gap at 0.5-0.6 that both shaders treat as the split
	float size_factor = is_small ? mix(0.15, 0.5, r3.y) : mix(0.6, 1.0, r3.y);

	if (gated_off) {
		// Still gets a normal spawn point, just invisible/motionless -- it
		// keeps its natural per-slot retry cadence identical to a real puff.
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
		TRANSFORM[2] = vec4(0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);
		VELOCITY = vec3(0.0);
	} else {
		float scale_mult = is_small ? small_scale_mult : 1.0;
		float base_scale = mix(start_scale_min, start_scale_max, r2.x) * scale_mult;
		TRANSFORM[0] = vec4(base_scale, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, base_scale, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, base_scale, 0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);

		float rise_mult = is_small ? small_rise_speed_mult : 1.0;
		float speed = rise_speed * (1.0 - rise_speed_variance * 0.5 + rise_speed_variance * r2.y) * rise_mult;
		vec3 horiz_jitter = mat3(EMISSION_TRANSFORM) * vec3(
			(r.x - 0.5) * side_drift,
			0.0,
			(r.y - 0.5) * side_drift
		);
		vec3 base_velocity = vec3(0.0, speed, 0.0) + horiz_jitter;

		// inertia: launch with a share of the emitter's current velocity,
		// then drag in process() lets it fall behind into a trail over time
		VELOCITY = base_velocity + EMITTER_VELOCITY * velocity_inherit_ratio;
	}

	CUSTOM.x = r.x * TAU;                                        // spin/orientation seed for draw shader
	CUSTOM.y = gated_off ? -(size_factor + 0.001) : size_factor;  // sign = gated flag, magnitude = size
	CUSTOM.z = r2.y * TAU;                                        // wobble/spin phase
	CUSTOM.w = 0.0;                                               // life progress 0..1
}

void process() {
	float seed = float(INDEX) + 0.5;
	vec2 r2 = hash21(seed + 91.7);

	bool gated = CUSTOM.y < 0.0;
	float size_factor = abs(CUSTOM.y);
	bool is_small = size_factor < 0.55;

	float lifetime_mult = is_small ? small_lifetime_mult : 1.0;
	float lifetime = mix(lifetime_min, lifetime_max, r2.x) * lifetime_mult;

	float progress = clamp(CUSTOM.w + DELTA / lifetime, 0.0, 1.0);
	CUSTOM.w = progress;

	if (!gated) {
		// Quantize TIME to a low tick rate just for the wobble oscillation,
		// so it visibly "steps" instead of gliding smoothly (position
		// integration below still uses real DELTA, so rise speed etc. are
		// unaffected).
		float wobble_time = floor(TIME * wobble_fps) / max(wobble_fps, 0.0001);

		VELOCITY.y += buoyancy * DELTA;
		VELOCITY.x += sin(wobble_time * wobble_freq + CUSTOM.z) * wobble_amount * DELTA;
		VELOCITY.z += cos(wobble_time * wobble_freq + CUSTOM.z) * wobble_amount * DELTA;

		// air resistance on the inherited emitter velocity -- lets the
		// plume fall behind into a wake instead of coasting alongside
		// the emitter forever
		VELOCITY.x -= VELOCITY.x * horizontal_drag * DELTA;
		VELOCITY.z -= VELOCITY.z * horizontal_drag * DELTA;

		// TRANSFORM is already world-space (local_coords = false)
		TRANSFORM[3].xyz += VELOCITY * DELTA;

		float scale_mult = is_small ? small_scale_mult : 1.0;
		float base_scale = mix(start_scale_min, start_scale_max, r2.x) * scale_mult;
		float scale = base_scale * mix(1.0, end_scale_mult, pow(progress, scale_curve_power));

		TRANSFORM[0] = vec4(scale, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, scale, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, scale, 0.0);
	}
	// gated particles: stay at zero scale/velocity as set in start(), just
	// age silently in place until they naturally die and re-roll the gate.

	ACTIVE = progress < 1.0;
}
