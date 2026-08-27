extends Player
class_name PlayerFish

@export_group("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 2.0
@export var deceleration: float = 1.0
@export var turn_speed: float = 1.1
@export var turn_acceleration: float = 1.5
@export var turn_deceleration: float = 2.5
@export var drift_factor: float = 0.64
@export var model : BoatModel

var _current_speed: float = 0.0
var _current_turn_rate: float = 0.0

@export_group("Physics")
@export var gravity: float = 20.0
@export var float_weight : float = 10.0

@export_group("Camera")
@export var camera_target: Node3D
@export var cam_rig : CameraRig

var _bob_time: float = 0.0
var playing_minigame: bool = false

func _ready() -> void:
	super.set_meta("float_weight", float_weight)
	super._ready()

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	move_and_slide()



func _handle_movement(delta: float) -> void:
	if not playing_minigame:
		var throttle := Input.get_axis("boat_reverse", "boat_forward")
		var steer := Input.get_axis("boat_turn_left", "boat_turn_right")

		# --- Speed: heavier ramp using exponential smoothing instead of linear move_toward ---
		var target_speed := throttle * max_speed
		if throttle != 0.0:
			_current_speed = lerp(_current_speed, target_speed, 1.0 - exp(-acceleration * delta))
		else:
			_current_speed = lerp(_current_speed, 0.0, 1.0 - exp(-deceleration * delta))

		model.rotate_prop(_current_speed, delta, throttle >= 0.0)

		# --- Turning: rudder takes time to bite, and the hull takes time to respond ---
		var turn_effectiveness = clamp(abs(_current_speed) / max_speed, 0.2, 1.0)
		var target_turn_rate = steer * turn_speed * turn_effectiveness

		if steer != 0.0:
			_current_turn_rate = move_toward(_current_turn_rate, target_turn_rate, turn_acceleration * delta)
		else:
			_current_turn_rate = move_toward(_current_turn_rate, 0.0, turn_deceleration * delta)

		rotate_y(-_current_turn_rate * delta)
		model.turn_rudder(steer, turn_speed, delta)

		var forward := -global_transform.basis.z
		var target_velocity := forward * _current_speed

		velocity.x = lerp(velocity.x, target_velocity.x, 1.0 - drift_factor)
		velocity.z = lerp(velocity.z, target_velocity.z, 1.0 - drift_factor)

		model.aim_lights(cam_rig.get_ray_target(), delta)

func catch_fish(fish: Fish) -> void:
	UtilityStates.add_item(fish)
	print("Caught fish")