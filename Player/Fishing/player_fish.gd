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

@export_group("Camera")
@export var camera_target: Node3D
@export var cam_rig : CameraRig

@export_group("UI Objects")
@export var analog_motion_sensor : AnalogMotionSensor

@export_group("Border")
@export var border_steer_gain: float = 2.0

var _wobble_time: float = 0.0
var _wobble_offset: float = 0.0

var _boost_speed: float = 0.0
var _current_speed: float = 0.0
var _current_turn_rate: float = 0.0
var _boost_rotation_velocity: float = 0.0

var playing_minigame: bool = false
var _minigame_position: Vector3 = Vector3.ZERO

var _border_active: bool = false
var _border_push_direction: Vector3 = Vector3.ZERO
var _border_intensity: float = 0.0

func _ready() -> void:
	_wobble_offset = randf_range(0.0, TAU)

	super.set_meta("float_weight", float_weight)
	super._ready()

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	move_and_slide()

func _handle_movement(delta: float) -> void:
	if not playing_minigame:
		var throttle: float
		var steer: float

		if _border_active:
			# Simulated input: drive forward and steer toward the return point,
			# same as if the player were holding those inputs themselves.
			throttle = 1.0

			var to_target := _border_push_direction
			to_target.y = 0.0

			if to_target.length() > 0.001:
				var forward_dir := -global_transform.basis.z
				var angle_to_target := forward_dir.signed_angle_to(to_target.normalized(), Vector3.UP)
				steer = clamp(-angle_to_target * border_steer_gain, -1.0, 1.0)
			else:
				steer = 0.0
		else:
			throttle = Input.get_axis("boat_reverse", "boat_forward")
			steer = Input.get_axis("boat_turn_left", "boat_turn_right")

		if throttle > 0.0:
			analog_motion_sensor.forward(delta)
		elif throttle < 0.0:
			analog_motion_sensor.reverse(delta)
		else:
			analog_motion_sensor.neutral(delta)

		# Wobble
		_wobble_time += delta

		var wobble_main = sin((_wobble_time * wobble_speed) + _wobble_offset)
		var wobble_secondary = sin((_wobble_time * wobble_speed * 0.47) + _wobble_offset * 1.7)
		var wobble_slow = sin((_wobble_time * wobble_speed * 0.19) + _wobble_offset * 2.3)

		var wobble_noise = sin((_wobble_time * wobble_random_speed) + _wobble_offset * 3.1)

		var wobble = (wobble_main * 0.6 + wobble_secondary * 0.25 + wobble_slow * 0.15)

		wobble *= 1.0 + (wobble_noise * wobble_randomness)
		wobble *= deg_to_rad(wobble_amount)

		var base_rotation := model.rotation
		base_rotation.z = 0.0

		model.rotation = base_rotation
		model.rotate_z(wobble)

		# Speed
		var current_max_speed := max_speed + _boost_speed
		var target_speed := throttle * current_max_speed

		if throttle != 0.0:
			# Boost
			var boosting := Input.is_action_pressed("boost")

			var boost_rotation := 0.0

			if boosting:
				model.boost(30)

				boost_rotation = deg_to_rad(rotation_angle)

				cam_rig.camera.change_fov(boost_fov, delta)
				_boost_speed = move_toward(_boost_speed, max_boost_speed, boost_acceleration * delta)
			else:
				model.boost(4)

				cam_rig.camera.change_fov(normal_fov, delta)
				_boost_speed = move_toward(_boost_speed, 0.0, boost_deceleration * delta)

			var rotation_difference := boost_rotation - model.rotation.x

			_boost_rotation_velocity += rotation_difference * rotation_speed * delta
			_boost_rotation_velocity *= exp(-rotation_damping * delta)

			model.rotation.x += _boost_rotation_velocity * delta

			for collision in collision_shapes:
				collision.rotation.x += _boost_rotation_velocity * delta

			_current_speed = lerp(_current_speed, target_speed, 1.0 - exp(-acceleration * delta))
		else:
			_current_speed = lerp(_current_speed, 0.0, 1.0 - exp(-deceleration * delta))

		model.rotate_prop(_current_speed, delta, throttle >= 0.0)

		# Turning
		var turn_effectiveness = clamp(abs(_current_speed) / max_speed, 0.0, 1.0)
		var target_turn_rate = steer * turn_speed * turn_effectiveness

		if steer != 0.0:
			_current_turn_rate = move_toward(_current_turn_rate, target_turn_rate, turn_acceleration * delta)
		else:
			_current_turn_rate = move_toward(_current_turn_rate, 0.0, turn_deceleration * delta)

		rotate_y(-_current_turn_rate * delta)
		model.turn_rudder(steer, turn_speed, delta)

		var forward := -global_transform.basis.z
		var target_velocity := forward * _current_speed

		velocity.x = lerp(velocity.x, target_velocity.x, (1.0 - drift_factor) * delta * 10.0)
		velocity.z = lerp(velocity.z, target_velocity.z, (1.0 - drift_factor) * delta * 10.0)

		model.aim_lights(cam_rig.get_ray_target(), delta)
	else:
		_current_speed = 0.0
		velocity = Vector3.ZERO
		global_position = _minigame_position

		analog_motion_sensor.neutral(delta)

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
	_border_intensity = intensity
	_border_push_direction = push_direction

	cam_rig.camera.darken_vision(intensity)

func clear_border() -> void:
	_border_active = false
	_border_intensity = 0.0

	cam_rig.camera.darken_vision(0.0)
