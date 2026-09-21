extends Area3D
class_name WorldBorder

@export var return_target : Marker3D

## Seconds of being inside before the push effect reaches full
@export var ramp_in_time : float = 1.5

var _time_inside : float = 0.0
var _overlapping_player : PlayerFish = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body : Node3D) -> void:
	if body is PlayerFish:
		_overlapping_player = body
		_time_inside = 0.0

func _on_body_exited(body : Node3D) -> void:
	if body is PlayerFish:
		_overlapping_player.clear_border()
		_overlapping_player = null
		_time_inside = 0.0

func _physics_process(delta: float) -> void:
	if _overlapping_player == null:
		return
	
	_time_inside = min(_time_inside + delta, ramp_in_time)
	var intensity := 1.0 if ramp_in_time <= 0.0 else _time_inside / ramp_in_time

	var push_direction := Vector3.ZERO
	if return_target:
		push_direction = return_target.global_position - _overlapping_player.global_position
	else:
		printerr("%s: return_target not set!" % self.name)
	
	_overlapping_player.darken_vision(intensity, push_direction)