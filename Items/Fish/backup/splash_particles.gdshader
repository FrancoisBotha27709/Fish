shader_type particles;

// ============================================================================
//  SPLASH PARTICLES  -  PROCESS shader   (Godot 4.x, GPUParticles3D)
//
//  Pair with:  splash_droplet.gdshader  on the Draw Pass (QuadMesh, size 1x1)
//
//  What it does
//   - Most particles are DROPLETS: they spray out of the splash spot, fly in
//     an arc (gravity, wind, drag, flutter) and stretch along their velocity.
//   - Every Nth particle is a SPLASH RIPPLE: a flat expanding ring lying on
//     the water surface at the splash spot.
//   - When a droplet comes back down it can die, bounce, and/or turn into a
//     tiny LANDING RIPPLE where it hits the surface.
//
//  Frame of reference
//   The splash spot is this node's origin. Its local XZ plane (Y = ground_height)
//   is the "water surface". Rotate the node to splash against walls/slopes.
//   Do NOT scale the node - use effect_scale instead.
//
//  Node settings that matter
//   Amount        ~ 40-100
//   Lifetime      ~ 1.0-2.0   (droplet flight + ripples all happen inside this)
//   Explosiveness 0.8-1.0 = one punchy burst, 0 = continuous spray
//   One Shot      on for event splashes (call restart() to trigger)
//   Local Coords  OFF (ripples/droplets stay where they were created)
//   Visibility AABB: make it big enough to contain the spray
// ============================================================================

group_uniforms Global;
// Scales everything uniformly: sizes, speeds, distances, gravity.
uniform float effect_scale = 1.0;
uniform vec3 gravity_accel = vec3(0.0, -9.8, 0.0);
uniform vec3 wind = vec3(0.0, 0.0, 0.0);
uniform float drag : hint_range(0.0, 20.0) = 0.4;
group_uniforms;

group_uniforms spawn;
uniform float spawn_radius = 0.02;          // droplets start scattered on a disc this wide
uniform float spawn_height = 0.0;           // start height above the splash spot
uniform float spawn_height_jitter = 0.0;    // random extra height
uniform float ground_height = 0.0;          // where the water surface is (local Y)
group_uniforms;

group_uniforms launch;
// Angles are measured from the node's up axis. 0 = straight up.
uniform float cone_min_angle : hint_range(0.0, 180.0) = 0.0;
uniform float cone_max_angle : hint_range(0.0, 180.0) = 50.0;
uniform float cone_bias : hint_range(0.1, 5.0) = 1.0;   // >1 = more droplets near min angle
uniform float speed_min = 1.0;
uniform float speed_max = 3.0;
uniform float speed_bias : hint_range(0.1, 5.0) = 1.0;  // >1 = more slow droplets
group_uniforms;

group_uniforms droplet;
uniform float size_min = 0.012;
uniform float size_max = 0.035;
uniform float size_pop_time : hint_range(0.0, 1.0) = 0.05;   // grow-in time (fraction of life)
uniform float shrink_start : hint_range(0.0, 0.99) = 0.7;    // when shrinking begins
uniform float size_end_scale : hint_range(0.0, 2.0) = 0.4;   // size multiplier at end of life
uniform float stretch_per_speed = 0.1;                       // streak length per unit of speed
uniform float max_stretch : hint_range(1.0, 20.0) = 3.0;
uniform float life_min : hint_range(0.01, 1.0) = 0.45;       // fractions of the node's Lifetime
uniform float life_max : hint_range(0.01, 1.0) = 0.8;
uniform float flutter = 0.3;                                 // random air wobble
uniform float flutter_freq = 12.0;
group_uniforms;

group_uniforms landing;
// 0 = fall through, 1 = vanish, 2 = become a ripple, 3 = bounce then ripple
uniform int landing_mode : hint_enum("Fall Through", "Vanish", "Land As Ripple", "Bounce Then Ripple") = 2;
uniform float bounce_restitution : hint_range(0.0, 1.0) = 0.3;
uniform float bounce_friction : hint_range(0.0, 1.0) = 0.6;
uniform float bounce_min_speed = 0.35;       // below this a bounce becomes a landing
uniform float landing_ripple_start_radius = 0.004;
uniform float landing_ripple_end_radius = 0.04;
uniform float landing_ripple_size_variation : hint_range(0.0, 1.0) = 0.3;
uniform float landing_ripple_life : hint_range(0.01, 1.0) = 0.35;
uniform float ripple_height_offset = 0.0005; // lifts ripples off the surface (stops z-fighting)
group_uniforms;

group_uniforms splash_spot;
uniform int ripple_every : hint_range(0, 256) = 12;   // every Nth particle is a ripple (0 = none)
uniform float ripple_scatter = 0.0;                   // random offset of ripple centre
uniform float ripple_radius_start = 0.02;
uniform float ripple_radius_end = 0.22;
uniform float ripple_life : hint_range(0.01, 1.0) = 0.7;
uniform float ripple_expand_ease : hint_range(0.1, 8.0) = 2.0;  // higher = fast start, slow finish
group_uniforms;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

float hash11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

// Quad lying flat on the emitter's XZ plane. (Built-ins can't be read inside
// helper functions, so the emission transform is passed in.)
mat4 flat_transform(mat4 et, vec3 lp, float diameter) {
	float d = max(diameter, 0.0001);
	mat4 m = mat4(
		vec4(d, 0.0, 0.0, 0.0),
		vec4(0.0, 0.0, -d, 0.0),
		vec4(0.0, d, 0.0, 0.0),
		vec4(lp, 1.0));
	return et * m;
}

// ---------------------------------------------------------------------------
// CUSTOM layout (read by the draw shader as INSTANCE_CUSTOM)
//   x = kind   0 droplet, 1 splash ripple, 2 landing ripple
//   y = normalised age of the current role (0..1)
//   z = per-particle random 0..1
//   w = seconds spent in the current role
// ---------------------------------------------------------------------------
void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	float rnd = rand_from_seed(seed);
	float s = effect_scale;
	mat4 et = EMISSION_TRANSFORM;
	COLOR = vec4(1.0);

	bool is_ripple = ripple_every > 0 && (INDEX % uint(ripple_every)) == uint(0);

	if (is_ripple) {
		float ang = rand_from_seed(seed) * 6.2831853;
		float rad = sqrt(rand_from_seed(seed)) * ripple_scatter * s;
		vec3 lp = vec3(cos(ang) * rad, (ground_height + ripple_height_offset) * s, sin(ang) * rad);
		CUSTOM = vec4(1.0, 0.0, rnd, 0.0);
		VELOCITY = vec3(0.0);
		TRANSFORM = flat_transform(et, lp, ripple_radius_start * 2.0 * s);
	} else {
		// Position: random point on a disc around the splash spot
		float ang = rand_from_seed(seed) * 6.2831853;
		float rad = sqrt(rand_from_seed(seed)) * spawn_radius * s;
		float h = (spawn_height + rand_from_seed(seed) * spawn_height_jitter) * s;
		vec3 lp = vec3(cos(ang) * rad, h, sin(ang) * rad);

		// Direction: random azimuth, elevation inside the cone
		float az = rand_from_seed(seed) * 6.2831853;
		float u = pow(rand_from_seed(seed), cone_bias);
		float elev = radians(mix(cone_min_angle, cone_max_angle, u));
		vec3 dir = vec3(sin(elev) * cos(az), cos(elev), sin(elev) * sin(az));

		float v = pow(rand_from_seed(seed), speed_bias);
		float spd = mix(speed_min, speed_max, v) * s;

		CUSTOM = vec4(0.0, 0.0, rnd, 0.0);
		VELOCITY = (et * vec4(dir * spd, 0.0)).xyz;

		mat4 m = mat4(1.0);
		m[3] = vec4(lp, 1.0);
		TRANSFORM = et * m;
	}
}

void process() {
	mat4 et = EMISSION_TRANSFORM;
	float s = effect_scale;
	float t = CUSTOM.w + DELTA;
	CUSTOM.w = t;
	float rnd = CUSTOM.z;

	if (CUSTOM.x < 0.5) {
		// ============================ DROPLET ============================
		float life = LIFETIME * mix(life_min, life_max, hash11(rnd * 1.31));
		float age = t / max(life, 0.0001);
		CUSTOM.y = age;
		if (age >= 1.0) {
			ACTIVE = false;
		}

		// Forces
		vec3 vel = VELOCITY;
		vec3 acc = (gravity_accel + wind) * s;
		acc += flutter * s * vec3(
			sin(t * flutter_freq + rnd * 40.0),
			sin(t * flutter_freq * 1.3 + rnd * 91.0),
			cos(t * flutter_freq * 0.9 + rnd * 63.0));
		vel += acc * DELTA;
		vel *= exp(-drag * DELTA);
		VELOCITY = vel;

		// Landing on the water surface (emitter-local XZ plane)
		bool converted = false;
		if (landing_mode != 0 && ACTIVE) {
			mat4 inv = inverse(et);
			float gh = ground_height * s;
			vec3 nxt = TRANSFORM[3].xyz + vel * DELTA;
			vec3 lp = (inv * vec4(nxt, 1.0)).xyz;
			vec3 vl = (inv * vec4(vel, 0.0)).xyz;

			if (lp.y < gh && vl.y < 0.0) {
				if (landing_mode == 1) {
					ACTIVE = false;
					converted = true;
				} else {
					bool do_bounce = landing_mode == 3 && (-vl.y * bounce_restitution) > bounce_min_speed * s;
					if (do_bounce) {
						vl.y = -vl.y * bounce_restitution;
						vl.x *= bounce_friction;
						vl.z *= bounce_friction;
						lp.y = gh;
						TRANSFORM[3].xyz = (et * vec4(lp, 1.0)).xyz;
						VELOCITY = (et * vec4(vl, 0.0)).xyz;
					} else {
						float rv = mix(1.0 - landing_ripple_size_variation, 1.0 + landing_ripple_size_variation, hash11(rnd * 3.3));
						CUSTOM.x = 2.0;
						CUSTOM.y = 0.0;
						CUSTOM.w = 0.0;
						VELOCITY = vec3(0.0);
						TRANSFORM = flat_transform(et, vec3(lp.x, gh + ripple_height_offset * s, lp.z), landing_ripple_start_radius * 2.0 * s * rv);
						converted = true;
					}
				}
			}
		}

		// Orientation + size (draw shader reads these from the transform columns:
		// column 1 = streak axis * length, column 0 = width)
		if (!converted) {
			float speed = length(VELOCITY);
			vec3 vdir = speed > 0.0001 ? VELOCITY / speed : vec3(0.0, -1.0, 0.0);
			float grow = size_pop_time > 0.0 ? smoothstep(0.0, size_pop_time, age) : 1.0;
			float shrink = mix(1.0, size_end_scale, smoothstep(shrink_start, 1.0, age));
			float size = mix(size_min, size_max, hash11(rnd * 7.77)) * s * grow * shrink;
			float stretch = 1.0 + min(speed / max(s, 0.0001) * stretch_per_speed, max(max_stretch - 1.0, 0.0));

			vec3 up = abs(vdir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 perp = normalize(cross(up, vdir));
			vec3 third = cross(perp, vdir);
			TRANSFORM[0] = vec4(perp * size, 0.0);
			TRANSFORM[1] = vec4(vdir * size * stretch, 0.0);
			TRANSFORM[2] = vec4(third * size, 0.0);
		}
	} else {
		// ============================ RIPPLE =============================
		bool landing = CUSTOM.x > 1.5;
		float dur = LIFETIME * (landing ? landing_ripple_life : ripple_life);
		float age = t / max(dur, 0.0001);
		CUSTOM.y = age;
		if (age >= 1.0) {
			ACTIVE = false;
		}

		float e = 1.0 - pow(1.0 - clamp(age, 0.0, 1.0), ripple_expand_ease);
		float r0 = landing ? landing_ripple_start_radius : ripple_radius_start;
		float r1 = landing ? landing_ripple_end_radius : ripple_radius_end;
		float rv = landing ? mix(1.0 - landing_ripple_size_variation, 1.0 + landing_ripple_size_variation, hash11(rnd * 3.3)) : 1.0;
		float diameter = max(mix(r0, r1, e) * 2.0 * s * rv, 0.0001);

		vec3 bx = normalize(TRANSFORM[0].xyz);
		vec3 by = normalize(TRANSFORM[1].xyz);
		vec3 bz = normalize(TRANSFORM[2].xyz);
		TRANSFORM[0] = vec4(bx * diameter, 0.0);
		TRANSFORM[1] = vec4(by * diameter, 0.0);
		TRANSFORM[2] = vec4(bz * diameter, 0.0);
		VELOCITY = vec3(0.0);
	}
}
