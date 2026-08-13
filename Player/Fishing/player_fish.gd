extends Player
class_name PlayerFish

@export_group("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 2.0
@export var deceleration: float = 1.0
@export var turn_speed: float = 1.1
@export var drift_factor: float = 0.64

@export_group("Physics")
@export var gravity: float = 20.0
@export var float_weight : float = 10.0

@export_group("Camera")
@export var camera_target: Node3D

var _bob_time: float = 0.0
var _current_speed: float = 0.0
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

		var turn_effectiveness = clamp(abs(_current_speed) / max_speed, 0.2, 1.0)
		rotate_y(-steer * turn_speed * turn_effectiveness * delta)

		if throttle != 0.0:
			_current_speed = move_toward(_current_speed, throttle * max_speed, acceleration * delta)
		else:
			_current_speed = move_toward(_current_speed, 0.0, deceleration * delta)

	var forward := -global_transform.basis.z
	var target_velocity := forward * _current_speed

	velocity.x = lerp(velocity.x, target_velocity.x, 1.0 - drift_factor)
	velocity.z = lerp(velocity.z, target_velocity.z, 1.0 - drift_factor)

func catch_fish(fish: Fish) -> void:
	UtilityStates.add_item(fish)
	print("Caught fish")
