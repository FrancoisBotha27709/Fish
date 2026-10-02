extends Player
class_name PlayerFish

@export_group("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 2.0
@export var deceleration: float = 1.0
@export var turn_speed: float = 0.65
@export var turn_acceleration: float = 0.8
@export var turn_deceleration: float = 0.5
@export var drift_factor: float = 0.85
@export var model : BoatModel

@export_group("Boost")
@export var rotation_angle : float = 5.0
@export var rotation_speed : float = 12.0
@export var rotation_damping : float = 4.0
@export var max_boost_speed: float = 6.0
@export var boost_acceleration: float = 5.0
@export var boost_deceleration: float = 8.0

@export_subgroup("Boost FOV")
@export var normal_fov: float = 60.0
@export var boost_fov: float = 78.0
@export var fov_change_speed: float = 25.0

@export_subgroup("Wobble")
@export var wobble_amount: float = 0.4
@export var wobble_speed: float = 7.0
@export var wobble_randomness: float = 0.35
@export var wobble_random_speed: float = 0.8

@export_group("Physics")
@export var gravity: float = 20.0
@export var float_weight : float = 10.0
@export_subgroup("Collisions")
@export var collision_shapes : Array[CollisionShape3D] = []
@export_subgroup("Buoyancy Gate")
@export var buoyancy_system: BuoyancySys
@export var min_submersion_to_move: float = 0.4  # fraction of hull height that must be underwater
@export var submersion_hysteresis: float = 0.15  # extra submersion needed to count as back in the water

@export_group("Land")
@export var land_align_speed: float = 3.0      # how quickly the boat settles onto terrain (lower = heavier)
@export var land_friction: float = 1.5         # horizontal slow-down while beached (0 = slides forever)

@export_group("Camera")
@export var camera_target: Node3D
@export var cam_rig : CameraRig

@export_group("UI Objects")
@export var analog_motion_sensor : AnalogMotionSensor

@export_group("Border")
@export var border_steer_gain: float = 2.0

## Read by BuoyancySys to stop forcing the hull level while on land.
var is_out_of_water := false
var playing_minigame := false

var _wobble_time := 0.0
var _wobble_offset := 0.0
var _boost_speed := 0.0
var _current_speed := 0.0
var _current_turn_rate := 0.0
var _boost_rotation_velocity := 0.0
var _minigame_position := Vector3.ZERO
var _border_active := false
var _border_push_direction := Vector3.ZERO

func _ready() -> void:
	_wobble_offset = randf_range(0.0, TAU)
	set_meta("float_weight", float_weight)
	super._ready()

func _physics_process(delta: float) -> void:
	if playing_minigame:
		_current_speed = 0.0
		velocity = Vector3.ZERO
		global_position = _minigame_position
		analog_motion_sensor.neutral(delta)
	else:
		_handle_movement(delta)
		if is_out_of_water: _handle_land(delta)
	move_and_slide()

# Gravity comes from BuoyancySys, so only orientation and friction live here.
func _handle_land(delta: float) -> void:
	if is_on_floor():
		var n := get_floor_normal()
		var fwd := (-global_basis.z).slide(n).normalized()
		var target := Basis(fwd.cross(n).normalized(), n, -fwd).get_rotation_quaternion()
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target, 1.0 - exp(-land_align_speed * delta)))
	var f := clampf(land_friction * delta, 0.0, 1.0)
	velocity *= Vector3(1.0 - f, 1.0, 1.0 - f)

func _handle_movement(delta: float) -> void:
	var throttle: float
	var steer: float
	if _border_active: # simulated input: drive forward and steer toward the return point
		throttle = 1.0
		var to := Vector3(_border_push_direction.x, 0.0, _border_push_direction.z)
		steer = clampf(-(-global_basis.z).signed_angle_to(to.normalized(), Vector3.UP) * border_steer_gain, -1.0, 1.0) if to.length() > 0.001 else 0.0
	else:
		throttle = Input.get_axis("boat_reverse", "boat_forward")
		steer = Input.get_axis("boat_turn_left", "boat_turn_right")

	# Hull must be sufficiently underwater to respond to input (hysteresis stops waterline flicker)
	is_out_of_water = buoyancy_system != null and buoyancy_system.get_submersion(self) < min_submersion_to_move + (submersion_hysteresis if is_out_of_water else 0.0)
	if is_out_of_water:
		throttle = 0.0
		steer = 0.0

	analog_motion_sensor.call(["reverse", "neutral", "forward"][int(signf(throttle)) + 1], delta)

	# Wobble
	_wobble_time += delta
	var t := _wobble_time * wobble_speed
	var wobble := sin(t + _wobble_offset) * 0.6 + sin(t * 0.47 + _wobble_offset * 1.7) * 0.25 + sin(t * 0.19 + _wobble_offset * 2.3) * 0.15
	wobble *= (1.0 + sin(_wobble_time * wobble_random_speed + _wobble_offset * 3.1) * wobble_randomness) * deg_to_rad(wobble_amount)
	model.rotation.z = 0.0
	model.rotate_z(wobble)

	# Speed + boost
	if throttle != 0.0:
		var target_speed := throttle * (max_speed + _boost_speed)
		var boosting := Input.is_action_pressed("boost")
		model.boost(30 if boosting else 4)
		cam_rig.camera.change_fov(boost_fov if boosting else normal_fov, delta)
		_boost_speed = move_toward(_boost_speed, max_boost_speed if boosting else 0.0, (boost_acceleration if boosting else boost_deceleration) * delta)
		_boost_rotation_velocity += (deg_to_rad(rotation_angle if boosting else 0.0) - model.rotation.x) * rotation_speed * delta
		_boost_rotation_velocity *= exp(-rotation_damping * delta)
		model.rotation.x += _boost_rotation_velocity * delta
		for c in collision_shapes: c.rotation.x += _boost_rotation_velocity * delta
		_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-acceleration * delta))
	else:
		_current_speed = lerpf(_current_speed, 0.0, 1.0 - exp(-deceleration * delta))
	model.rotate_prop(_current_speed, delta, throttle >= 0.0)

	# Turning
	var target_turn := steer * turn_speed * clampf(absf(_current_speed) / max_speed, 0.0, 1.0)
	_current_turn_rate = move_toward(_current_turn_rate, target_turn if steer != 0.0 else 0.0, (turn_acceleration if steer != 0.0 else turn_deceleration) * delta)
	rotate_y(-_current_turn_rate * delta)
	model.turn_rudder(steer, turn_speed, delta)

	# Drift toward the drive velocity; while beached momentum carries (see _handle_land)
	if not is_out_of_water:
		var k := (1.0 - drift_factor) * delta * 10.0
		var target_velocity := -global_basis.z * _current_speed
		velocity.x = lerpf(velocity.x, target_velocity.x, k)
		velocity.z = lerpf(velocity.z, target_velocity.z, k)

	model.aim_lights(cam_rig.get_ray_target(), delta)

func start_minigame() -> void:
	playing_minigame = true
	_minigame_position = global_position
	velocity = Vector3.ZERO

func end_minigame() -> void:
	playing_minigame = false

func catch_fish(fish: Fish) -> void:
	UtilityStates.add_item(fish)
	print("Caught fish")

func darken_vision(intensity: float, push_direction: Vector3) -> void:
	_border_active = true
	_border_push_direction = push_direction
	cam_rig.camera.darken_vision(intensity)

func clear_border() -> void:
	_border_active = false
	cam_rig.camera.darken_vision(0.0)