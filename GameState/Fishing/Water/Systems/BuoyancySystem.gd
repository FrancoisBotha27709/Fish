extends Node
class_name BuoyancySys
## Emitted the frame a floating body first touches the water (transitions
## from not-submerged to submerged). body = the object that entered,
## world_pos = the point used for the splash (shape-centered origin,
## same point spawn_ripple gets called with).
signal object_entered_water(body: Node3D, world_pos: Vector3)

## Emitted the frame a floating body leaves the water entirely
## (transitions from submerged to not-submerged — e.g. a boat cresting a
## wave, a jumping fish, an object lifted out).
signal object_exited_water(body: Node3D, world_pos: Vector3)

@export var water_path: NodePath           # -> MeshInstance3D running WaterManager.gd
@export var water_base_height: float = 0.0 # world-space Y of calm sea level
@export var gravity: float = 9.8

@export_group("Buoyancy")
@export var buoyancy_multiplier: float = 1.3   # scales buoyant force overall; >1 so bodies settle partly submerged, not fully underwater. Lowered from 1.6 — less overshoot/bounce at the waterline.
@export var water_density: float = 1000.0      # reference density used with shape volume to compute buoyant force — NOT tied to any body's own mass, which is what lets weight actually matter
@export var default_weight: float = 1.0        # used by any floatable with no RigidBody mass and no "float_weight" metadata override
@export var linear_drag: float = 6.0           # raised from 4.0 — kills vertical bounce faster
@export var angular_drag: float = 4.0          # raised from 2.5 — kills rocking overshoot faster
@export var min_damping_factor: float = 0.4    # raised from 0.25 — damping never drops below this fraction of full strength, even right at the waterline, so barely-submerged objects stop oscillating across the surface sooner
@export var sample_corners: bool = true        # 4-corner sampling = rocking/tilting + boat tilt; false = cheaper single center sample, no tilt

@export_group("Spawn Safety")
@export var max_vertical_speed: float = 4.0    # lowered from 6.0 — hard clamp on buoyancy-driven vertical speed for every body type. This is what actually stops "shoots into the sky" launches; lowering it also caps how hard a body can bounce at all.
@export var spawn_ease_time: float = 1.0       # raised from 0.6 — seconds over which buoyant force ramps from 0% to 100% after a body is first seen in the "floating" group. Longer ease = softer entry for objects that spawn already underwater.

@export_group("Boat Tilt")
@export var enable_boat_tilt: bool = true      # rock/tilt to match the local wave slope
@export var tilt_speed: float = 3.0            # CharacterBody3D/Area3D/Node3D: base rate orientation catches up to the wave slope, for an object at tilt_reference_size/tilt_reference_weight
@export var align_torque_strength: float = 3.0 # RigidBody3D-only (non-frozen): base torque pulling "up" toward the wave normal, same reference point. Lowered from 4.0 to reduce rocking overshoot.
@export var tilt_reference_size: float = 1.0   # meters (average half-extent) considered a "normal" object for tilt-speed scaling
@export var tilt_reference_weight: float = 1.0 # float_weight considered a "normal" object for tilt-speed scaling
@export var tilt_size_influence: float = 1.0   # 0 = size doesn't affect tilt rate; 1 = full inverse scaling (double the size -> half the rate)
@export var tilt_weight_influence: float = 1.0 # 0 = weight doesn't affect tilt rate; 1 = full inverse scaling (double the weight -> half the rate)

@export_group("Stick To Surface")
@export var stick_to_surface_depth: float = 0.15      # world units the object's collision-shape center sits below the local water surface
@export var stick_to_surface_follow_speed: float = 5.0 # lowered from 8.0 — softer/slower correction toward the surface-locked height, less visible snap now that the RigidBody freeze fix removes the physics-server fight entirely

@export_group("Wake")
@export var wake_min_speed: float = 0.3
@export var wake_interval: float = 0.25
@export var wake_strength: float = 0.6
@export var splash_strength: float = 1.6

var _water: Node = null
var _shape_cache: Dictionary = {}         # instance_id -> {half: Vector3, center: Vector3, stick: bool}, computed once per body
var _wake_timer: Dictionary = {}          # instance_id -> float
var _was_submerged: Dictionary = {}       # instance_id -> bool
var _manual_vel_y: Dictionary = {}        # instance_id -> float; vertical velocity for Area3D/plain Node3D (no native physics velocity)
var _first_seen: Dictionary = {}          # instance_id -> float (elapsed time when first processed), used for spawn_ease_time
var _elapsed_time: float = 0.0

func _ready() -> void:
	_water = get_node_or_null(water_path)
	if _water == null:
		push_warning("BuoyancySystem: water_path is not set or invalid; buoyancy will run but ripples won't be spawned.")

func _physics_process(delta: float) -> void:
	_elapsed_time += delta
	for body in get_tree().get_nodes_in_group("floating"):
		if _is_stick_to_surface(body):
			_process_stick_to_surface(body, delta)
		elif body is RigidBody3D:
			_process_rigid_body(body, delta)
		elif body is CharacterBody3D:
			_process_character_body(body, delta)
		elif body is Node3D:
			# Area3D and anything else with no native physics velocity —
			# still gets full weight-based float/sink, just via a manually
			# tracked vertical velocity instead of the physics engine.
			_process_manual_body(body, delta)

# ---------------------------------------------------------------- weight

## Public so custom controllers (or other systems) can query the same
## weight this node uses, e.g. to react to "am I heavy cargo or not".
func get_weight(body: Node3D) -> float:
	if body.has_meta("float_weight"):
		return max(float(body.get_meta("float_weight")), 0.01)
	if body is RigidBody3D:
		return max(body.mass, 0.01)
	return max(default_weight, 0.01)

## True if this floatable should skip the weight/force simulation and be
## pinned to "just under the surface" instead. Set via a "stick_to_surface"
## boolean metadata entry (Node dock > Metadata) — no script required.
## Cached alongside the shape data (see _get_shape_data) since it's read
## every physics frame per body; call refresh_stick_flag() if you flip the
## metadata on a body at runtime after it's already been cached.
func _is_stick_to_surface(body: Node3D) -> bool:
	if "stick_to_surface" in body:
		return bool(body.get("stick_to_surface"))
	return false
## Call if a body's "stick_to_surface" metadata changes after it's already
## been cached (e.g. toggling behavior at runtime). Forces the next frame
## to re-read metadata and, for a RigidBody3D, re-evaluate freeze state.
func refresh_stick_flag(body: Node3D) -> void:
	_shape_cache.erase(body.get_instance_id())

## Buoyant force at FULL submersion, in Newtons-equivalent — deliberately a
## function of shape volume only, never of the body's own weight/mass.
func _buoyant_force_full(half: Vector3) -> float:
	var volume := half.x * 2.0 * half.y * 2.0 * half.z * 2.0
	return water_density * gravity * volume * buoyancy_multiplier

## 0..1 ramp applied to buoyant force based on how long this body has been
## tracked. Prevents an object that spawns already deep underwater from
## getting 100% force on its very first frame — the main source of the
## "shoots into the sky" launch, independent of the max_vertical_speed clamp.
func _get_spawn_ease(body: Node3D) -> float:
	var id := body.get_instance_id()
	if not _first_seen.has(id):
		_first_seen[id] = _elapsed_time
	if spawn_ease_time <= 0.0:
		return 1.0
	var t: float = _elapsed_time - _first_seen[id]
	return clamp(t / spawn_ease_time, 0.0, 1.0)

# --------------------------------------------------------------- tilt rate

## Scales tilt_speed / align_torque_strength down for objects bigger and/or
## heavier than the reference size/weight — a big heavy object should tilt
## noticeably slower than a small light one, not at the same rate.
func _tilt_response_scale(body: Node3D, half: Vector3, weight: float) -> float:
	if "tilt_multiplier" in body:
		return max(float(body.get("tilt_multiplier")), 0.001)
	var size_metric: float = (half.x + half.y + half.z) / 3.0
	var size_term: float = pow(max(tilt_reference_size / max(size_metric, 0.001), 0.001), tilt_size_influence)
	var weight_term: float = pow(max(tilt_reference_weight / max(weight, 0.001), 0.001), tilt_weight_influence)
	return size_term * weight_term

# ---------------------------------------------------------------- geometry

## Returns {half: Vector3, center: Vector3, stick: bool} for a floatable's
## collision shape — half-extents for the volume/submersion math, "center"
## as the CollisionShape3D's local offset from the body (Vector3.ZERO if
## it's centered on the body's own origin), and the cached stick_to_surface
## flag. All buoyancy sampling anchors on body.global_transform * center
## rather than body.global_position, so an off-center collider still
## floats/tilts about its actual middle.
##
## If the body is a RigidBody3D and stick_to_surface is true, this also
## freezes it (kinematic) the first time it's seen so this node becomes
## the sole authority over its transform — see the STICK TO SURFACE /
## RigidBody3D note at the top of this file for why that matters.
func _get_shape_data(body: Node3D) -> Dictionary:
	var id := body.get_instance_id()
	if _shape_cache.has(id):
		return _shape_cache[id]

	var half_extents := Vector3(0.5, 0.5, 0.5)
	var local_center := Vector3.ZERO
	for child in body.get_children():
		if child is CollisionShape3D and child.shape:
			var aabb := _shape_local_aabb(child.shape)
			half_extents = aabb.size * 0.5 * child.scale
			local_center = child.position
			break

	var stick: bool = _is_stick_to_surface(body)

	if stick and body is RigidBody3D and not body.freeze:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	var data := {"half": half_extents, "center": local_center}
	_shape_cache[id] = data
	body.tree_exiting.connect(_on_floatable_freed.bind(id))
	return data

func _shape_local_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		return AABB(-shape.size * 0.5, shape.size)
	if shape is SphereShape3D:
		var d = shape.radius * 2.0
		return AABB(Vector3(-shape.radius, -shape.radius, -shape.radius), Vector3(d, d, d))
	if shape is CapsuleShape3D:
		var h = shape.height
		var r = shape.radius
		return AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
	if shape is CylinderShape3D:
		var h2 = shape.height
		var r2 = shape.radius
		return AABB(Vector3(-r2, -h2 * 0.5, -r2), Vector3(r2 * 2.0, h2, r2 * 2.0))
	# Fallback for shapes we don't special-case (convex/concave meshes, etc).
	# Tune manually per-object if this is too rough for something important.
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))

func _corner_offsets(half: Vector3, basis: Basis) -> Array[Vector3]:
	if not sample_corners:
		return [Vector3.ZERO]
	return [
		basis * Vector3(half.x, 0, half.z),
		basis * Vector3(-half.x, 0, half.z),
		basis * Vector3(half.x, 0, -half.z),
		basis * Vector3(-half.x, 0, -half.z),
	]

# ------------------------------------------------------------ water height

func _water_height_at(world_pos: Vector3) -> float:
	if _water == null:
		return water_base_height
	# Prefer the full wave+ripple surface height; fall back to ripple-only
	# if an older/simpler water script is ever swapped in.
	if _water.has_method("get_water_height_at"):
		return water_base_height + _water.get_water_height_at(Vector2(world_pos.x, world_pos.z))
	if _water.has_method("get_ripple_height_at"):
		return water_base_height + _water.get_ripple_height_at(Vector2(world_pos.x, world_pos.z))
	return water_base_height

# --------------------------------------------------------- wave slope / tilt

## Estimates the local wave-surface normal from 4 corner samples (water
## height at each corner, forming a quad). Falls back to straight up if
## corners aren't available or are degenerate.
func _estimate_wave_normal(origin: Vector3, corners: Array[Vector3], corner_water_y: Array[float]) -> Vector3:
	if corners.size() < 4 or corner_water_y.size() < 4:
		return Vector3.UP
	var p0 := origin + corners[0]; p0.y = corner_water_y[0]
	var p1 := origin + corners[1]; p1.y = corner_water_y[1]
	var p2 := origin + corners[2]; p2.y = corner_water_y[2]
	var p3 := origin + corners[3]; p3.y = corner_water_y[3]
	var n1 := (p1 - p0).cross(p2 - p0)
	var n2 := (p3 - p2).cross(p0 - p2)
	var normal := n1 + n2
	if normal.length_squared() < 0.0001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.y < 0.0:
		normal = -normal
	return normal

## Smoothly blends a kinematic body's orientation toward the local wave
## slope while preserving its current heading (yaw) — used for
## CharacterBody3D, Area3D, plain Node3D, and frozen (stick_to_surface)
## RigidBody3D. Non-frozen RigidBody3D uses a torque instead (see
## _process_rigid_body) so normal physics does the rocking. rate_scale
## comes from _tilt_response_scale — bigger/heavier bodies blend slower.
func _apply_visual_tilt(body: Node3D, origin: Vector3, corners: Array[Vector3], corner_water_y: Array[float], strength: float, delta: float, rate_scale: float) -> void:
	var wave_normal := _estimate_wave_normal(origin, corners, corner_water_y)
	var current_basis: Basis = body.global_transform.basis
	var forward: Vector3 = -current_basis.z # Godot forward is -Z
	var right: Vector3 = forward.cross(wave_normal)
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var new_forward: Vector3 = wave_normal.cross(right).normalized()
	var scale := current_basis.get_scale()
	var target_basis := Basis(right, wave_normal, -new_forward).orthonormalized()

	var current_quat := current_basis.orthonormalized().get_rotation_quaternion()
	var target_quat := target_basis.get_rotation_quaternion()
	var blend: float = clamp(tilt_speed * rate_scale * delta * clamp(strength, 0.0, 1.0), 0.0, 1.0)
	var new_quat := current_quat.slerp(target_quat, blend)

	var t := body.global_transform
	t.basis = Basis(new_quat).scaled(scale)
	body.global_transform = t

# ------------------------------------------------------------- rigid body

func _process_rigid_body(body: RigidBody3D, delta: float) -> void:
	if body.name.contains("Buoy"):
		print(body.name, " path=", body.get_path(), " id=", body.get_instance_id(),
			" stick_check=", _is_stick_to_surface(body), " stick_val=", body.get("stick_to_surface"))
	var shape := _get_shape_data(body)
	var half: Vector3 = shape.half
	var origin: Vector3 = body.global_transform * shape.center
	var body_origin: Vector3 = body.global_position
	var basis: Basis = body.global_transform.basis
	var corners := _corner_offsets(half, basis)
	var weight := get_weight(body)
	var ase := _get_spawn_ease(body)

	var buoyant_force_full := _buoyant_force_full(half) * ase
	var force_per_sample := buoyant_force_full / corners.size()

	var any_submerged := false
	var max_ratio := 0.0
	var corner_water_y: Array[float] = []
	for offset in corners:
		var world_pos: Vector3 = origin + offset
		var water_y := _water_height_at(world_pos)
		corner_water_y.append(water_y)
		var bottom_y := world_pos.y - half.y
		var submersion: float = clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)
		if submersion <= 0.0:
			continue
		any_submerged = true
		max_ratio = max(max_ratio, submersion)
		# Buoyant force is volume-based (see _buoyant_force_full), NOT
		# scaled by body.mass — a light RigidBody accelerates up strongly
		# relative to its own weight; a heavy one of the same size barely
		# gets pushed at all and sinks. apply_force's position is relative
		# to the body's own origin, so re-base the shape-centered offset.
		var apply_pos: Vector3 = (origin - body_origin) + offset
		body.apply_force(Vector3(0, force_per_sample * submersion, 0), apply_pos)

	if any_submerged:
		# Damp toward zero vertical/angular velocity directly rather than
		# fighting the buoyant force with an opposing force — force-vs-force
		# damping is prone to underdamped bounce. min_damping_factor keeps
		# a damping floor even when barely submerged, so the body doesn't
		# oscillate back and forth across the waterline.
		var damp: float = lerp(min_damping_factor, 1.0, max_ratio)
		body.linear_velocity.y = lerp(body.linear_velocity.y, 0.0, clamp(linear_drag * damp * delta, 0.0, 1.0))
		body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, clamp(angular_drag * damp * delta, 0.0, 1.0))

		if enable_boat_tilt and sample_corners and corners.size() == 4:
			var wave_normal := _estimate_wave_normal(origin, corners, corner_water_y)
			var current_up: Vector3 = body.global_transform.basis.y
			# Proportional align torque: current_up.cross(target_up) points
			# in the direction that rotates current_up toward target_up.
			# body.mass keeps force scaling consistent across masses (as
			# before); _tilt_response_scale additionally slows big/heavy
			# objects beyond what their own inertia already does.
			var align_torque := current_up.cross(wave_normal) * align_torque_strength * _tilt_response_scale(body, half, weight) * body.mass * max_ratio
			body.apply_torque(align_torque)

	# Hard clamp — no matter how large the computed force/ratio was, vertical
	# speed can never exceed this. This is what actually stops launch spikes.
	body.linear_velocity.y = clamp(body.linear_velocity.y, -max_vertical_speed, max_vertical_speed)

	_handle_wake(body, origin, any_submerged, delta)

# --------------------------------------------------------- character body

func _process_character_body(body: CharacterBody3D, delta: float) -> void:
	var shape := _get_shape_data(body)
	var half: Vector3 = shape.half
	var origin: Vector3 = body.global_transform * shape.center
	var basis: Basis = body.global_transform.basis
	var corners := _corner_offsets(half, basis)

	var weight := get_weight(body)
	var ase := _get_spawn_ease(body)
	var buoyant_force_full := _buoyant_force_full(half) * ase

	var total_submersion := 0.0
	var corner_water_y: Array[float] = []
	for offset in corners:
		var world_pos: Vector3 = origin + offset
		var water_y := _water_height_at(world_pos)
		corner_water_y.append(water_y)
		var bottom_y := world_pos.y - half.y
		var submersion: float = clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)
		total_submersion += submersion
	var avg_submersion: float = total_submersion / float(corners.size())
	var any_submerged := avg_submersion > 0.0

	# CAVEAT: this node now owns velocity.y ENTIRELY for any CharacterBody3D
	# tagged "floatable" — both while submerged (buoyancy) and while not
	# (gravity), same as a RigidBody would. If the body's own controller
	# script (e.g. a player/boat movement script) ALSO applies its own
	# gravity to velocity.y every physics frame, the two will double up and
	# fight based on node Process Priority. Delete/guard that block in the
	# controller once a body is handled here (e.g.
	# `if not is_in_group("floating"): velocity.y -= gravity * delta`).
	# If you'd rather the controller stay in full charge, skip this
	# automatic push (remove the body from "floating" or early-return here)
	# and call get_submersion(body)/get_weight(body) yourself instead.
	if any_submerged:
		var buoyant_accel: float = (buoyant_force_full * avg_submersion) / weight
		body.velocity.y += (buoyant_accel - gravity) * delta
		# Damping floor (min_damping_factor) so the last bit of bounce right
		# at the waterline actually gets killed instead of lingering.
		var damp: float = lerp(min_damping_factor, 1.0, avg_submersion)
		body.velocity.y -= body.velocity.y * clamp(linear_drag * damp * delta, 0.0, 1.0)
	elif not body.is_on_floor():
		body.velocity.y -= gravity * delta
	else:
		body.velocity.y = 0.0

	# Hard clamp — same launch-spike protection as the RigidBody path.
	body.velocity.y = clamp(body.velocity.y, -max_vertical_speed, max_vertical_speed)

	if enable_boat_tilt and sample_corners and corners.size() == 4:
		var rate_scale := _tilt_response_scale(body, half, weight)
		_apply_visual_tilt(body, origin, corners, corner_water_y, avg_submersion, delta, rate_scale)

	_handle_wake(body, origin, any_submerged, delta)

## Optional query for character controllers that want to handle their own
## swimming logic instead of the automatic push above.
func get_submersion(body: Node3D) -> float:
	var shape := _get_shape_data(body)
	var half: Vector3 = shape.half
	var origin: Vector3 = body.global_transform * shape.center
	var water_y := _water_height_at(origin)
	var bottom_y := origin.y - half.y
	return clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)

# --------------------------------------------------- manual bodies (Area3D, etc.)

## Area3D and any other Node3D in "floatable" that isn't a RigidBody3D or
## CharacterBody3D. These have no physics-native vertical motion, so this
## node tracks a manual vertical velocity per instance and moves
## global_position directly — same weight-based float/sink math as
## everything else, just integrated by hand.
func _process_manual_body(body: Node3D, delta: float) -> void:
	var shape := _get_shape_data(body)
	var half: Vector3 = shape.half
	var origin: Vector3 = body.global_transform * shape.center
	var basis: Basis = body.global_transform.basis
	var corners := _corner_offsets(half, basis)

	var weight := get_weight(body)
	var ase := _get_spawn_ease(body)
	var buoyant_force_full := _buoyant_force_full(half) * ase

	var total_submersion := 0.0
	var corner_water_y: Array[float] = []
	for offset in corners:
		var world_pos: Vector3 = origin + offset
		var water_y := _water_height_at(world_pos)
		corner_water_y.append(water_y)
		var bottom_y := world_pos.y - half.y
		var submersion: float = clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)
		total_submersion += submersion
	var avg_submersion: float = total_submersion / float(corners.size())
	var any_submerged := avg_submersion > 0.0

	var id := body.get_instance_id()
	var vel_y: float = _manual_vel_y.get(id, 0.0)

	if any_submerged:
		var buoyant_accel: float = (buoyant_force_full * avg_submersion) / weight
		vel_y += (buoyant_accel - gravity) * delta
		var damp: float = lerp(min_damping_factor, 1.0, avg_submersion)
		vel_y -= vel_y * clamp(linear_drag * damp * delta, 0.0, 1.0)
	else:
		# Not touching the water at all - fall freely so it actually
		# reaches the surface instead of hovering in place.
		vel_y -= gravity * delta

	# Hard clamp — same launch-spike protection as the other two paths.
	vel_y = clamp(vel_y, -max_vertical_speed, max_vertical_speed)
	_manual_vel_y[id] = vel_y

	var new_pos := body.global_position
	new_pos.y += vel_y * delta
	body.global_position = new_pos

	if enable_boat_tilt and sample_corners and corners.size() == 4:
		var rate_scale := _tilt_response_scale(body, half, weight)
		_apply_visual_tilt(body, origin, corners, corner_water_y, avg_submersion, delta, rate_scale)

	_handle_wake(body, new_pos, any_submerged, delta)

# --------------------------------------------------------- stick to surface

## For any floatable with "stick_to_surface" metadata set true. Skips the
## weight/force simulation entirely: the shape center is locked to
## "local water height - stick_to_surface_depth", smoothed with
## stick_to_surface_follow_speed, and hard-clamped so it can never rise
## above the surface. Still tilts with the wave slope exactly like a
## normal floatable, via the same visual blend everything else uses.
##
## RigidBody3D bodies are frozen (kinematic) the first time they're seen
## here (in _get_shape_data) specifically so this function's direct
## global_position writes are the only thing moving them — otherwise the
## physics server keeps integrating gravity/collision response on the body
## in between this node's writes, which is what caused the jittering/
## "bouncing" behavior. Because it's frozen, torque does nothing, so it
## uses _apply_visual_tilt like every other body type instead of
## apply_torque.
##
## Deliberately does NOT call _handle_wake: a stick_to_surface object is
## always "in" the water by definition, so treating that as a wake/ripple
## source would fire ripples every single frame.
func _process_stick_to_surface(body: Node3D, delta: float) -> void:
	var shape := _get_shape_data(body)
	var half: Vector3 = shape.half
	var origin: Vector3 = body.global_transform * shape.center
	var basis: Basis = body.global_transform.basis
	var corners := _corner_offsets(half, basis)

	var corner_water_y: Array[float] = []
	for offset in corners:
		corner_water_y.append(_water_height_at(origin + offset))
	var water_y_center := _water_height_at(origin)

	# Target: shape center sits stick_to_surface_depth below the surface,
	# and can never end up above it (min() below is the hard clamp).
	var target_center_y: float = min(water_y_center - stick_to_surface_depth, water_y_center - 0.001)
	var current_center_y: float = origin.y
	var new_center_y: float = lerp(current_center_y, target_center_y, clamp(stick_to_surface_follow_speed * delta, 0.0, 1.0))
	new_center_y = min(new_center_y, water_y_center - 0.001) # safety net if follow_speed overshoots

	var delta_y: float = new_center_y - current_center_y
	var new_pos := body.global_position
	new_pos.y += delta_y
	body.global_position = new_pos

	# We own vertical motion directly, so zero out whatever velocity
	# tracking that body type would otherwise use for buoyancy. For a
	# RigidBody3D this is now frozen (see _get_shape_data), so this is
	# mostly a formality — but harmless to keep as a safety net.
	if body is RigidBody3D:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	elif body is CharacterBody3D:
		body.velocity.y = 0.0
	else:
		_manual_vel_y[body.get_instance_id()] = 0.0

	if enable_boat_tilt and sample_corners and corners.size() == 4:
		var weight := get_weight(body)
		var rate_scale := _tilt_response_scale(body, half, weight)
		_apply_visual_tilt(body, origin, corners, corner_water_y, 1.0, delta, rate_scale)

	# No _handle_wake call here — see doc comment above.

# ------------------------------------------------------------------ wake

func _handle_wake(body: Node3D, world_pos: Vector3, submerged: bool, delta: float) -> void:
	var id := body.get_instance_id()
	var was: bool = _was_submerged.get(id, false)

	if submerged and not was:
		_spawn_ripple(world_pos, splash_strength)
		object_entered_water.emit(body, world_pos)
		_wake_timer[id] = 0.0
	elif was and not submerged:
		object_exited_water.emit(body, world_pos)
	_was_submerged[id] = submerged

	if not submerged:
		return

	var speed := 0.0
	if body is RigidBody3D:
		speed = Vector2(body.linear_velocity.x, body.linear_velocity.z).length()
	elif body is CharacterBody3D:
		speed = Vector2(body.velocity.x, body.velocity.z).length()
	else:
		var vel_y: float = _manual_vel_y.get(id, 0.0)
		speed = abs(vel_y) # manual bodies have no horizontal velocity tracked; wake reacts to bobbing only

	if speed < wake_min_speed:
		return

	_wake_timer[id] = _wake_timer.get(id, 0.0) + delta
	if _wake_timer[id] >= wake_interval:
		_wake_timer[id] = 0.0
		_spawn_ripple(world_pos, clamp(speed / 10.0, 0.2, 1.0) * wake_strength)

func _spawn_ripple(world_pos: Vector3, strength: float) -> void:
	if _water and _water.has_method("spawn_ripple"):
		_water.spawn_ripple(world_pos, strength)

# --------------------------------------------------------------- cleanup

func _on_floatable_freed(id: int) -> void:
	_shape_cache.erase(id)
	_wake_timer.erase(id)
	_was_submerged.erase(id)
	_manual_vel_y.erase(id)
	_first_seen.erase(id)
