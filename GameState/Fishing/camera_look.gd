extends Camera3D
class_name CameraLook

@export_range(0.1, 20.0, 0.1) var vision_darken_speed : float = 3.0

var _vision_darken_target: float = 0.0
var _vision_darken_current: float = 0.0

func _process(delta: float) -> void:
	if not is_equal_approx(_vision_darken_current, _vision_darken_target):
		_vision_darken_current = move_toward(_vision_darken_current, _vision_darken_target, vision_darken_speed * delta)
		_apply_vision_darken()

func change_fov(target_fov: float, delta: float) -> void:
	fov = move_toward(fov, target_fov, 20.0 * delta)

func darken_vision(intensity: float) -> void:
	_vision_darken_target = clamp(intensity, 0.0, 1.0)

func _apply_vision_darken() -> void:
	#grade_brightness = lerp(1.0, 0.1, _vision_darken_current)
	#grade_saturation = lerp(1.0, 0.0, _vision_darken_current)
	SignalBus.darken_vision_changed.emit(_vision_darken_current)