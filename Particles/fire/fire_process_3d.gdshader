shader_type particles;
// Drives fire particle motion in 3D. Assign as the GPUParticles3D
// "Process Material". Pairs with fire_draw_3d.gdshader.
//
// WORLD-SPACE SIMULATION: written for local_coords = false on the
// GPUParticles3D node, so already-emitted licks are NOT dragged along when
// the node moves (gives the flame trailing inertia as the emitter moves).
// Because of that, TRANSFORM here is a WORLD-space transform -- the engine
// does not multiply it by the node's transform for us. So start() manually
// converts the local emission offset into world space using
// EMISSION_TRANSFORM (the node's global transform at spawn), and pulls in
// EMITTER_VELOCITY to inherit the emitter's motion. Also set
// inherit_velocity_ratio = 1.0 on the GPUParticles3D node itself -- that's
// what makes the engine populate EMITTER_VELOCITY; velocity_inherit_ratio
// below then controls how much of it each new lick actually keeps.
//
// EMISSION-INTENSITY GATING (replaces changing `amount` / amount_ratio):
// `amount` is a fixed pool sized for the maximum flame intensity and must
// never change at runtime. Instead, FireSmoke.gd smoothly drives
// `emission_intensity` (0..1) every frame. Each particle slot gets a fixed,
// INDEX-derived `activation_threshold` computed ONCE in start(). If that
// threshold is above the current emission_intensity, the slot still lives
// out a normal lifetime cycle (so its natural respawn cadence is
// unaffected) but is parked invisibly (zero scale, zero velocity) instead
// of behaving like a real flame lick. As emission_intensity rises, more
// slots pass their threshold on their next natural respawn -- staggered
// across the whole pool -- giving a gradual intensity increase with no
// pop-in. This is decoupled from ACTIVE = progress < 1.0 below: gating only
// ever touches visibility/motion, never the death timer.

// ==================== Emission control ====================
uniform float emission_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float spawn_hash_seed = 11.0; // vary per-emitter to desync multiple fire nodes

// ==================== Ember (small spark) variation ====================
// Disabled by default (ember_ratio = 0) so fire behaves exactly like the
// original shader unless you opt in.
uniform float ember_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float ember_scale_mult : hint_range(0.05, 1.0) = 0.4;
uniform float ember_lifetime_mult : hint_range(0.1, 2.0) = 0.5;
uniform float ember_rise_speed_mult : hint_range(0.1, 4.0) = 1.6;

// ==================== Emission shape ====================
uniform float emission_radius : hint_range(0.0, 10.0) = 0.3;

// ==================== Motion ====================
uniform float rise_speed : hint_range(0.0, 10.0) = 1.8;
uniform float rise_speed_variance : hint_range(0.0, 1.0) = 0.4;
uniform float side_drift : hint_range(0.0, 5.0) = 0.5;
uniform float wobble_freq : hint_range(0.0, 10.0) = 2.5;
uniform float wobble_amount : hint_range(0.0, 5.0) = 0.3;
// Stepped-time rate for the wobble oscillation only (position integration
// stays continuous). At 60 this is identical to plain TIME (fully smooth).
// Lower it (e.g. 30, 12, 8) to make the wobble visibly "update" on a slower
// tick, like it's animated at a lower frame rate, without touching rise
// speed, lifetime, or anything else.
uniform float wobble_fps : hint_range(1.0, 60.0) = 60.0;
uniform float buoyancy : hint_range(0.0, 5.0) = 0.6;
uniform float horizontal_drag : hint_range(0.0, 10.0) = 2.5; // bleeds off inherited emitter velocity
uniform float velocity_inherit_ratio : hint_range(0.0, 1.0) = 0.85;

// ==================== Lifetime & scale ====================
uniform float lifetime_min = 0.6;
uniform float lifetime_max = 1.1;
uniform float start_scale_min = 0.15;
uniform float start_scale_max = 0.3;
uniform float end_scale_mult = 0.35; // shrinks as it burns out
uniform float scale_curve_power : hint_range(0.1, 4.0) = 1.0; // 1 = linear burn-down, >1 = holds size then shrinks fast

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

	// spawn inside a small disc, in the emitter's LOCAL XZ plane
	float ang = r.x * TAU;
	float rad = sqrt(r.y) * emission_radius;
	vec3 local_pos = vec3(cos(ang) * rad, 0.0, sin(ang) * rad);
	vec3 world_pos = (EMISSION_TRANSFORM * vec4(local_pos, 1.0)).xyz;

	bool is_ember = r3.x < ember_ratio;
	// continuous size value: embers cluster near the low end, full licks
	// near the high end, with a gap at 0.5-0.6 both shaders treat as the split
	float size_factor = is_ember ? mix(0.15, 0.5, r3.y) : mix(0.6, 1.0, r3.y);

	if (gated_off) {
		TRANSFORM[0] = vec4(0.0);
		TRANSFORM[1] = vec4(0.0);
		TRANSFORM[2] = vec4(0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);
		VELOCITY = vec3(0.0);
	} else {
		float scale_mult = is_ember ? ember_scale_mult : 1.0;
		float base_scale = mix(start_scale_min, start_scale_max, r2.x) * scale_mult;
		// keep the mesh axis-aligned to world space (not rotated with the
		// emitter) so licks still visually point "up" regardless of tilt --
		// only position tracks the emitter, not orientation
		TRANSFORM[0] = vec4(base_scale, 0.0, 0.0, 0.0);
		TRANSFORM[1] = vec4(0.0, base_scale, 0.0, 0.0);
		TRANSFORM[2] = vec4(0.0, 0.0, base_scale, 0.0);
		TRANSFORM[3] = vec4(world_pos, 1.0);

		float rise_mult = is_ember ? ember_rise_speed_mult : 1.0;
		float speed = rise_speed * (1.0 - rise_speed_variance * 0.5 + rise_speed_variance * r2.y) * rise_mult;
		vec3 horiz_jitter = mat3(EMISSION_TRANSFORM) * vec3((r.x - 0.5) * side_drift, 0.0, (r.y - 0.5) * side_drift);
		vec3 base_velocity = vec3(0.0, speed, 0.0) + horiz_jitter;

		// inertia: launch with a share of the emitter's current velocity,
		// then drag in process() lets it fall behind into a trail
		VELOCITY = base_velocity + EMITTER_VELOCITY * velocity_inherit_ratio;
	}

	CUSTOM.x = r.x * TAU;                                        // spin direction source for draw shader
	CUSTOM.y = gated_off ? -(size_factor + 0.001) : size_factor;  // sign = gated flag, magnitude = size
	CUSTOM.z = r2.y * TAU;                                        // per-particle wobble/flicker phase
	CUSTOM.w = 0.0;                                               // life progress 0..1
}

void process() {
	float seed = float(INDEX) + 0.5;
	vec2 r2 = hash21(seed + 91.7);

	bool gated = CUSTOM.y < 0.0;
	float size_factor = abs(CUSTOM.y);
	bool is_ember = size_factor < 0.55;

	float lifetime_mult = is_ember ? ember_lifetime_mult : 1.0;
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

		// air resistance on the inherited emitter velocity -- without this
		// the lick would just keep coasting alongside the emitter forever
		// instead of falling behind into a trail
		VELOCITY.x -= VELOCITY.x * horizontal_drag * DELTA;
		VELOCITY.z -= VELOCITY.z * horizontal_drag * DELTA;

		// TRANSFORM is already world-space (local_coords = false)
		TRANSFORM[3].xyz += VELOCITY * DELTA;

		float scale_mult = is_ember ? ember_scale_mult : 1.0;
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
