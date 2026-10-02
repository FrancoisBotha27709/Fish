extends Node
class_name BuoyancySys
## Emitted when a floating body first touches / fully leaves the water.
signal object_entered_water(body: Node3D, world_pos: Vector3)
signal object_exited_water(body: Node3D, world_pos: Vector3)

@export var water_path: NodePath           # -> MeshInstance3D running WaterManager.gd
@export var water_base_height: float = 0.0
@export var gravity: float = 9.8

@export_group("Buoyancy")
@export var buoyancy_multiplier: float = 1.3
@export var water_density: float = 1000.0
@export var default_weight: float = 1.0        # when no RigidBody mass / "float_weight" meta
@export var linear_drag: float = 6.0
@export var angular_drag: float = 4.0
@export var min_damping_factor: float = 0.4
@export var sample_corners: bool = true        # false = single center sample, no tilt

@export_group("Spawn Safety")
@export var max_vertical_speed: float = 4.0
@export var spawn_ease_time: float = 1.0       # seconds for buoyancy to ramp 0 -> 100% after first seen

@export_group("Boat Tilt")
@export var enable_boat_tilt: bool = true
@export var tilt_speed: float = 3.0
@export var align_torque_strength: float = 3.0 # RigidBody3D only
@export var tilt_reference_size: float = 1.0
@export var tilt_reference_weight: float = 1.0
@export var tilt_size_influence: float = 1.0
@export var tilt_weight_influence: float = 1.0
@export var recover_deg_per_sec: float = 6.0     # constant angular speed back to the wave slope after leaving land
@export var recover_done_angle_deg: float = 0.3  # recovery ends within this many degrees of the smoothed normal
@export var normal_smoothing: float = 1.5        # low-pass on the player boat's wave normal (lower = calmer)

@export_group("Stick To Surface")
@export var stick_to_surface_depth: float = 0.15
@export var stick_to_surface_follow_speed: float = 5.0

@export_group("Wake")
@export var wake_min_speed: float = 0.3
@export var wake_interval: float = 0.25
@export var wake_strength: float = 0.6
@export var splash_strength: float = 1.6

var _water: Node
var _time := 0.0
# Per-body state, keyed by instance id
var _cache := {}      # {half, center}
var _timer := {}      # wake timer
var _wet := {}        # was submerged
var _vy := {}         # manual vertical velocity (Area3D / Node3D)
var _first := {}      # first-seen time
var _recovering := {} # unwinding a land tilt
var _smooth := {}     # smoothed wave normal

func _ready() -> void:
	_water = get_node_or_null(water_path)
	if _water == null:
		push_warning("BuoyancySys: water_path invalid; buoyancy runs but no ripples.")

func _physics_process(delta: float) -> void:
	_time += delta
	for b in get_tree().get_nodes_in_group("floating"):
		if _is_stick(b): _stick(b, delta)
		elif b is RigidBody3D: _rigid(b, delta)
		elif b is CharacterBody3D: _character(b, delta)
		elif b is Node3D: _manual(b, delta)

# ------------------------------------------------------------ public

func get_weight(b: Node3D) -> float:
	if b.has_meta("float_weight"): return maxf(float(b.get_meta("float_weight")), 0.01)
	return maxf(b.mass if b is RigidBody3D else default_weight, 0.01)

## 0..1 fraction of the body's collision height under water at its center.
func get_submersion(b: Node3D) -> float:
	var sh := _shape(b)
	var o: Vector3 = b.global_transform * sh.center
	return clampf((_h(o) - (o.y - sh.half.y)) / maxf(sh.half.y * 2.0, 0.001), 0.0, 1.0)

## Call after changing "stick_to_surface" at runtime.
func refresh_stick_flag(b: Node3D) -> void:
	_cache.erase(b.get_instance_id())

# ------------------------------------------------------------ helpers

func _is_stick(b: Node3D) -> bool:
	return b.get("stick_to_surface") == true

## Surface height; waves_only skips ripples (used for hull tilt so the wake can't feed back).
func _h(p: Vector3, waves_only := false) -> float:
	var xz := Vector2(p.x, p.z)
	if _water:
		var methods: Array = ["get_water_height_at", "get_ripple_height_at"]
		if waves_only: methods.push_front("get_wave_height_at")
		for m in methods:
			if _water.has_method(m): return water_base_height + _water.call(m, xz)
	return water_base_height

func _shape(b: Node3D) -> Dictionary:
	var id := b.get_instance_id()
	if _cache.has(id): return _cache[id]
	var size := Vector3.ONE
	var center := Vector3.ZERO
	for c in b.get_children():
		if c is CollisionShape3D and c.shape:
			var s: Shape3D = c.shape
			if s is BoxShape3D: size = s.size
			elif s is SphereShape3D: size = Vector3.ONE * s.radius * 2.0
			elif s is CapsuleShape3D or s is CylinderShape3D: size = Vector3(s.radius * 2.0, s.height, s.radius * 2.0)
			size *= c.scale
			center = c.position
			break
	if _is_stick(b) and b is RigidBody3D and not b.freeze: # we become sole authority over its transform
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
	_cache[id] = {"half": size * 0.5, "center": center}
	b.tree_exiting.connect(_on_freed.bind(id))
	return _cache[id]

func _corners(half: Vector3, basis: Basis) -> Array[Vector3]:
	if not sample_corners: return [Vector3.ZERO]
	var out: Array[Vector3] = []
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		out.append(basis * Vector3(half.x * s.x, 0.0, half.z * s.y))
	return out

## Everything per-frame the body types need: per-corner water height / submersion, averages, force.
func _sample(b: Node3D) -> Dictionary:
	var sh := _shape(b)
	var half: Vector3 = sh.half
	var origin: Vector3 = b.global_transform * sh.center
	var corners := _corners(half, b.global_transform.basis)
	var ys: Array[float] = []
	var subs: Array[float] = []
	var total := 0.0
	var top := 0.0
	for o in corners:
		var p := origin + o
		var y := _h(p)
		var sub := clampf((y - (p.y - half.y)) / maxf(half.y * 2.0, 0.001), 0.0, 1.0)
		ys.append(y)
		subs.append(sub)
		total += sub
		top = maxf(top, sub)
	var id := b.get_instance_id()
	if not _first.has(id): _first[id] = _time
	var ease := 1.0 if spawn_ease_time <= 0.0 else clampf((_time - _first[id]) / spawn_ease_time, 0.0, 1.0)
	return {
		"half": half, "origin": origin, "corners": corners, "ys": ys, "subs": subs,
		"avg": total / corners.size(), "max": top, "weight": get_weight(b),
		# Full-submersion buoyant force: volume only, never body weight
		"force": water_density * gravity * half.x * half.y * half.z * 8.0 * buoyancy_multiplier * ease,
	}

## Vertical velocity step shared by CharacterBody3D and manual bodies.
func _vel_step(v: float, s: Dictionary, delta: float, on_floor := false) -> float:
	if s.avg > 0.0:
		v += (s.force * s.avg / s.weight - gravity) * delta
		v -= v * clampf(linear_drag * lerpf(min_damping_factor, 1.0, s.avg) * delta, 0.0, 1.0)
	elif not on_floor: v -= gravity * delta
	else: v = 0.0
	return clampf(v, -max_vertical_speed, max_vertical_speed)

# ------------------------------------------------------------ tilt

func _tilt_scale(b: Node3D, half: Vector3, weight: float) -> float:
	var m = b.get("tilt_multiplier")
	if m != null: return maxf(float(m), 0.001)
	var size := (half.x + half.y + half.z) / 3.0
	return pow(maxf(tilt_reference_size / maxf(size, 0.001), 0.001), tilt_size_influence) \
		* pow(maxf(tilt_reference_weight / maxf(weight, 0.001), 0.001), tilt_weight_influence)

## Wave-surface normal from the 4 corner heights (straight up if degenerate).
func _normal(origin: Vector3, c: Array[Vector3], y: Array[float]) -> Vector3:
	if c.size() < 4 or y.size() < 4: return Vector3.UP
	var p: Array[Vector3] = []
	for i in 4: p.append(Vector3(origin.x + c[i].x, y[i], origin.z + c[i].z))
	var n := (p[1] - p[0]).cross(p[2] - p[0]) + (p[3] - p[2]).cross(p[0] - p[2])
	if n.length_squared() < 0.0001: return Vector3.UP
	n = n.normalized()
	return n if n.y >= 0.0 else -n

## Blends the body toward the wave slope, keeping its heading. rec > 0 rotates at that many deg/sec
## (ignores weight/size/submersion) to unwind a land tilt; smooth low-passes the normal.
## Returns the angle (rad) between the body's up and the target normal before this frame's blend.
func _tilt(b: Node3D, s: Dictionary, ys: Array[float], strength: float, delta: float, rec := 0.0, smooth := false) -> float:
	var n := _normal(s.origin, s.corners, ys)
	var id := b.get_instance_id()
	if smooth:
		n = _smooth.get(id, n).slerp(n, 1.0 - exp(-normal_smoothing * delta)).normalized()
		_smooth[id] = n
	var basis := b.global_transform.basis
	var err := basis.y.normalized().angle_to(n)
	var right := (-basis.z).cross(n)
	if right.length_squared() < 0.0001: return err
	right = right.normalized()
	var target := Basis(right, n, -n.cross(right).normalized()).orthonormalized().get_rotation_quaternion()
	var cur := basis.orthonormalized().get_rotation_quaternion()
	var blend := clampf(tilt_speed * _tilt_scale(b, s.half, s.weight) * delta * clampf(strength, 0.0, 1.0), 0.0, 1.0)
	if rec > 0.0:
		var left := cur.angle_to(target)
		if left > 0.0001: blend = maxf(blend, clampf(deg_to_rad(rec) * delta / left, 0.0, 1.0))
	b.global_basis = Basis(cur.slerp(target, blend)).scaled(basis.get_scale())
	return err

# ------------------------------------------------------------ body types

func _rigid(b: RigidBody3D, delta: float) -> void:
	var s := _sample(b)
	var any: bool = s.max > 0.0
	var per: float = s.force / s.corners.size()
	for i in s.corners.size():
		if s.subs[i] > 0.0: # apply_force position is relative to the body origin
			b.apply_force(Vector3(0.0, per * s.subs[i], 0.0), s.origin - b.global_position + s.corners[i])
	if any:
		var d := lerpf(min_damping_factor, 1.0, s.max) # damp velocity directly; force-vs-force bounces
		b.linear_velocity.y = lerpf(b.linear_velocity.y, 0.0, clampf(linear_drag * d * delta, 0.0, 1.0))
		b.angular_velocity = b.angular_velocity.lerp(Vector3.ZERO, clampf(angular_drag * d * delta, 0.0, 1.0))
		if enable_boat_tilt and s.corners.size() == 4:
			b.apply_torque(b.global_basis.y.cross(_normal(s.origin, s.corners, s.ys)) \
				* align_torque_strength * _tilt_scale(b, s.half, s.weight) * b.mass * s.max)
	b.linear_velocity.y = clampf(b.linear_velocity.y, -max_vertical_speed, max_vertical_speed)
	_wake(b, s.origin, any, delta)

## This node owns velocity.y for CharacterBody3D in the "floating" group; don't also apply gravity in the controller.
func _character(b: CharacterBody3D, delta: float) -> void:
	var s := _sample(b)
	b.velocity.y = _vel_step(b.velocity.y, s, delta, b.is_on_floor())
	var id := b.get_instance_id()
	var beached: bool = b.get("is_out_of_water") == true # let it tilt with the terrain
	if beached:
		_recovering[id] = true
		_smooth.erase(id)
	elif enable_boat_tilt and s.corners.size() == 4:
		var rec: float = recover_deg_per_sec if _recovering.get(id, false) else 0.0
		var wy: Array[float] = []
		for o in s.corners: wy.append(_h(s.origin + o, true)) # ripple-free surface for tilt
		var err := _tilt(b, s, wy, s.avg, delta, rec, true)
		if rec > 0.0 and err < deg_to_rad(recover_done_angle_deg): _recovering.erase(id)
	_wake(b, s.origin, s.avg > 0.0, delta)

## Area3D / plain Node3D: no native velocity, so integrate vertical motion by hand.
func _manual(b: Node3D, delta: float) -> void:
	var s := _sample(b)
	var id := b.get_instance_id()
	var v := _vel_step(_vy.get(id, 0.0), s, delta)
	_vy[id] = v
	b.global_position.y += v * delta
	if enable_boat_tilt and s.corners.size() == 4: _tilt(b, s, s.ys, s.avg, delta)
	_wake(b, b.global_position, s.avg > 0.0, delta)

## Pinned just under the surface; no weight sim, no wake (it is always "in" the water).
func _stick(b: Node3D, delta: float) -> void:
	var s := _sample(b)
	var wy := _h(s.origin)
	var cur: float = s.origin.y
	var tgt := minf(wy - stick_to_surface_depth, wy - 0.001)
	var ny := minf(lerpf(cur, tgt, clampf(stick_to_surface_follow_speed * delta, 0.0, 1.0)), wy - 0.001)
	b.global_position.y += ny - cur
	if b is RigidBody3D:
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	elif b is CharacterBody3D: b.velocity.y = 0.0
	else: _vy[b.get_instance_id()] = 0.0
	if enable_boat_tilt and s.corners.size() == 4: _tilt(b, s, s.ys, 1.0, delta)

# ------------------------------------------------------------ wake

func _wake(b: Node3D, pos: Vector3, wet: bool, delta: float) -> void:
	var id := b.get_instance_id()
	var was: bool = _wet.get(id, false)
	if wet and not was:
		_ripple(pos, splash_strength)
		object_entered_water.emit(b, pos)
		_timer[id] = 0.0
	elif was and not wet: object_exited_water.emit(b, pos)
	_wet[id] = wet
	if not wet: return
	var speed: float = absf(_vy.get(id, 0.0)) # manual bodies: reacts to bobbing only
	if b is RigidBody3D: speed = Vector2(b.linear_velocity.x, b.linear_velocity.z).length()
	elif b is CharacterBody3D: speed = Vector2(b.velocity.x, b.velocity.z).length()
	if speed < wake_min_speed: return
	_timer[id] = _timer.get(id, 0.0) + delta
	if _timer[id] >= wake_interval:
		_timer[id] = 0.0
		_ripple(pos, clampf(speed / 10.0, 0.2, 1.0) * wake_strength)

func _ripple(pos: Vector3, strength: float) -> void:
	if _water and _water.has_method("spawn_ripple"): _water.spawn_ripple(pos, strength)

func _on_freed(id: int) -> void:
	for d in [_cache, _timer, _wet, _vy, _first, _recovering, _smooth]: d.erase(id)