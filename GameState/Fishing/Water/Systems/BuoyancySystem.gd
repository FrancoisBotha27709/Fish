class_name BuoyancySys
extends Node

signal object_entered_water(body: Node3D, world_pos: Vector3)
signal object_exited_water(body: Node3D, world_pos: Vector3)

@export var water_path: NodePath
@export var gravity := 9.8

@export_group("Buoyancy")
@export var buoyancy_multiplier := 1.3
@export var water_density := 1000.0
@export var default_weight := 1.0
@export var linear_drag := 6.0
@export var angular_drag := 4.0
@export var min_damping_factor := 0.4
@export var sample_corners := true

@export_group("Spawn Safety")
@export var max_vertical_speed := 4.0
@export var spawn_ease_time := 1.0

@export_group("Boat Tilt")
@export var enable_boat_tilt := true
@export var tilt_speed := 3.0
@export var align_torque_strength := 3.0
@export var tilt_reference_size := 1.0
@export var tilt_reference_weight := 1.0
@export var tilt_size_influence := 1.0
@export var tilt_weight_influence := 1.0
@export var recover_deg_per_sec := 6.0
@export var recover_done_angle_deg := 0.3
@export var normal_smoothing := 1.5

@export_group("Stick To Surface")
@export var stick_to_surface_depth := 0.15
@export var stick_to_surface_follow_speed := 5.0

@export_group("Wake")
@export var wake_min_speed := 0.3
@export var wake_interval := 0.25
@export var wake_strength := 0.6
@export var splash_strength := 1.6

class S:
	var half := Vector3.ONE * 0.5
	var ctr := Vector3.ZERO
	var t0 := -1.0
	var vy := 0.0
	var tw := 0.0
	var wet := false
	var rec := false
	var stick := false
	var nrm := Vector3.ZERO

const SG: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

var _w: WaterManager
var _t := 0.0
var _st := {}
var _n := 1
var _o := Vector3.ZERO
var _c := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _y := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _wy := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _sub := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _avg := 0.0
var _mx := 0.0
var _force := 0.0
var _wt := 1.0

func _ready() -> void:
	_w = get_node_or_null(water_path) as WaterManager
	if _w == null:
		push_warning("BuoyancySys: water_path invalid; using flat water at y=0")

func _physics_process(dt: float) -> void:
	_t += dt
	for n in get_tree().get_nodes_in_group("floating"):
		var b := n as Node3D
		if b == null:
			continue
		var s := _state(b)
		if s.stick:
			_stick(b, s, dt)
		elif b is RigidBody3D:
			_rigid(b, s, dt)
		elif b is CharacterBody3D:
			_char(b, s, dt)
		else:
			_manual(b, s, dt)

func get_weight(b: Node3D) -> float:
	var w: float = _p(b, &"float_weight", 0.0)
	if w > 0.0:
		return w
	return maxf(b.mass if b is RigidBody3D else default_weight, 0.01)

func get_submersion(b: Node3D) -> float:
	var s := _state(b)
	var o := b.global_transform * s.ctr
	return clampf((_at(o.x, o.z, true) - (o.y - s.half.y)) / maxf(s.half.y * 2.0, 0.001), 0.0, 1.0)

func refresh_stick_flag(b: Node3D) -> void:
	_st.erase(b.get_instance_id())

func _p(b: Node, k: StringName, d: Variant) -> Variant:
	var v: Variant = b.get(k)
	return v if v != null else (b.get_meta(k) if b.has_meta(k) else d)

func _at(x: float, z: float, rip: bool) -> float:
	if _w == null:
		return 0.0
	_w.prep(Vector2(x, z))
	var h := _w.global_position.y + _w.surface(x, z)
	return h + _w.ripples() if rip else h

func _state(b: Node3D) -> S:
	var id := b.get_instance_id()
	var s: S = _st.get(id)
	if s:
		return s
	s = S.new()
	for c in b.get_children():
		if c is CollisionShape3D and c.shape:
			var sh = c.shape
			var sz := Vector3.ONE
			if sh is BoxShape3D:
				sz = sh.size
			elif sh is SphereShape3D:
				sz = Vector3.ONE * sh.radius * 2.0
			elif sh is CapsuleShape3D or sh is CylinderShape3D:
				sz = Vector3(sh.radius * 2.0, sh.height, sh.radius * 2.0)
			s.half = sz * c.scale * 0.5
			s.ctr = c.position
			break
	s.stick = _p(b, &"stick_to_surface", false) == true
	if s.stick and b is RigidBody3D and not b.freeze:
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
	_st[id] = s
	b.tree_exiting.connect(_free.bind(id))
	return s

func _sample(b: Node3D, s: S) -> void:
	var xf := b.global_transform
	_o = xf * s.ctr
	_n = 4 if sample_corners else 1
	_wt = get_weight(b)
	if s.t0 < 0.0:
		s.t0 = _t
	var ease := 1.0 if spawn_ease_time <= 0.0 else clampf((_t - s.t0) / spawn_ease_time, 0.0, 1.0)
	_force = water_density * gravity * s.half.x * s.half.y * s.half.z * 8.0 * buoyancy_multiplier * ease
	var h2 := maxf(s.half.y * 2.0, 0.001)
	var y0 := 0.0
	if _w:
		_w.prep(Vector2(_o.x, _o.z))
		y0 = _w.global_position.y
	_avg = 0.0
	_mx = 0.0
	for i in _n:
		var c := Vector3.ZERO
		if _n == 4:
			c = xf.basis * Vector3(s.half.x * SG[i].x, 0.0, s.half.z * SG[i].y)
		_c[i] = c
		var w := y0
		var y := y0
		if _w:
			w += _w.surface(_o.x + c.x, _o.z + c.z)
			y = w + _w.ripples()
		var sub := clampf((y - (_o.y + c.y - s.half.y)) / h2, 0.0, 1.0)
		_wy[i] = w
		_y[i] = y
		_sub[i] = sub
		_avg += sub
		_mx = maxf(_mx, sub)
	_avg /= _n

func _vel(v: float, dt: float, floor_hit := false) -> float:
	if _avg > 0.0:
		v += (_force * _avg / _wt - gravity) * dt
		v -= v * clampf(linear_drag * lerpf(min_damping_factor, 1.0, _avg) * dt, 0.0, 1.0)
	elif not floor_hit:
		v -= gravity * dt
	else:
		v = 0.0
	return clampf(v, -max_vertical_speed, max_vertical_speed)

func _tilt_scale(b: Node3D, s: S) -> float:
	var m: Variant = _p(b, &"tilt_multiplier", null)
	if m != null:
		return maxf(float(m), 0.001)
	var sz := (s.half.x + s.half.y + s.half.z) / 3.0
	return pow(maxf(tilt_reference_size / maxf(sz, 0.001), 0.001), tilt_size_influence) * pow(maxf(tilt_reference_weight / maxf(_wt, 0.001), 0.001), tilt_weight_influence)

func _normal(y: PackedFloat32Array) -> Vector3:
	if _n < 4:
		return Vector3.UP
	var a := Vector3(_c[0].x, y[0], _c[0].z)
	var b := Vector3(_c[1].x, y[1], _c[1].z)
	var c := Vector3(_c[2].x, y[2], _c[2].z)
	var d := Vector3(_c[3].x, y[3], _c[3].z)
	var n := (b - a).cross(c - a) + (d - c).cross(a - c)
	if n.length_squared() < 0.0001:
		return Vector3.UP
	n = n.normalized()
	return n if n.y >= 0.0 else -n

func _tilt(b: Node3D, s: S, y: PackedFloat32Array, strength: float, dt: float, rec := 0.0, smooth := false) -> float:
	var n := _normal(y)
	if smooth:
		if s.nrm == Vector3.ZERO:
			s.nrm = n
		n = s.nrm.slerp(n, 1.0 - exp(-normal_smoothing * dt)).normalized()
		s.nrm = n
	var bs := b.global_transform.basis
	var err := bs.y.normalized().angle_to(n)
	var right := (-bs.z).cross(n)
	if right.length_squared() < 0.0001:
		return err
	right = right.normalized()
	var target := Basis(right, n, right.cross(n).normalized()).orthonormalized().get_rotation_quaternion()
	var cur := bs.orthonormalized().get_rotation_quaternion()
	var blend := clampf(tilt_speed * _tilt_scale(b, s) * dt * clampf(strength, 0.0, 1.0), 0.0, 1.0)
	if rec > 0.0:
		var left := cur.angle_to(target)
		if left > 0.0001:
			blend = maxf(blend, clampf(deg_to_rad(rec) * dt / left, 0.0, 1.0))
	b.global_basis = Basis(cur.slerp(target, blend)).scaled(bs.get_scale())
	return err

func _rigid(b: RigidBody3D, s: S, dt: float) -> void:
	_sample(b, s)
	var per := _force / _n
	var org := _o - b.global_position
	for i in _n:
		if _sub[i] > 0.0:
			b.apply_force(Vector3(0.0, per * _sub[i], 0.0), org + _c[i])
	if _mx > 0.0:
		var d := lerpf(min_damping_factor, 1.0, _mx)
		b.linear_velocity.y = lerpf(b.linear_velocity.y, 0.0, clampf(linear_drag * d * dt, 0.0, 1.0))
		b.angular_velocity = b.angular_velocity.lerp(Vector3.ZERO, clampf(angular_drag * d * dt, 0.0, 1.0))
		if enable_boat_tilt and _n == 4:
			b.apply_torque(b.global_basis.y.cross(_normal(_y)) * align_torque_strength * _tilt_scale(b, s) * b.mass * _mx)
	b.linear_velocity.y = clampf(b.linear_velocity.y, -max_vertical_speed, max_vertical_speed)
	_wake(b, s, _mx > 0.0, Vector2(b.linear_velocity.x, b.linear_velocity.z).length(), dt)

func _char(b: CharacterBody3D, s: S, dt: float) -> void:
	_sample(b, s)
	b.velocity.y = _vel(b.velocity.y, dt, b.is_on_floor())
	if b.get("is_out_of_water") == true:
		s.rec = true
		s.nrm = Vector3.ZERO
	elif enable_boat_tilt and _n == 4:
		var rec := recover_deg_per_sec if s.rec else 0.0
		var err := _tilt(b, s, _wy, _avg, dt, rec, true)
		if rec > 0.0 and err < deg_to_rad(recover_done_angle_deg):
			s.rec = false
	_wake(b, s, _avg > 0.0, Vector2(b.velocity.x, b.velocity.z).length(), dt)

func _manual(b: Node3D, s: S, dt: float) -> void:
	_sample(b, s)
	s.vy = _vel(s.vy, dt)
	b.global_position.y += s.vy * dt
	if enable_boat_tilt and _n == 4:
		_tilt(b, s, _y, _avg, dt)
	_wake(b, s, _avg > 0.0, absf(s.vy), dt)

func _stick(b: Node3D, s: S, dt: float) -> void:
	_sample(b, s)
	var wy := _at(_o.x, _o.z, true)
	var ny := minf(lerpf(_o.y, minf(wy - stick_to_surface_depth, wy - 0.001), clampf(stick_to_surface_follow_speed * dt, 0.0, 1.0)), wy - 0.001)
	b.global_position.y += ny - _o.y
	if b is RigidBody3D:
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	elif b is CharacterBody3D:
		b.velocity.y = 0.0
	s.vy = 0.0
	if enable_boat_tilt and _n == 4:
		_tilt(b, s, _y, 1.0, dt)

func _wake(b: Node3D, s: S, wet: bool, speed: float, dt: float) -> void:
	if wet and not s.wet:
		_ripple(_o, _p(b, &"splash_strength", splash_strength))
		object_entered_water.emit(b, _o)
		s.tw = 0.0
	elif s.wet and not wet:
		object_exited_water.emit(b, _o)
	s.wet = wet
	if not wet:
		return
	if _w:
		var bx := b.global_basis.x
		_w.stamp_hull(_o, Vector2(s.half.x, s.half.z), Vector2(bx.x, bx.z).normalized(), clampf(0.35 + speed * 0.12, 0.0, 1.0))
	if speed < wake_min_speed:
		return
	s.tw += dt
	if s.tw >= wake_interval:
		s.tw = 0.0
		_ripple(_o, clampf(speed / 10.0, 0.2, 1.0) * float(_p(b, &"wake_strength", wake_strength)))

func _ripple(p: Vector3, k: float) -> void:
	if _w:
		_w.spawn_ripple(p, k)

func _free(id: int) -> void:
	_st.erase(id)
