extends Node2D
class_name AnalogMotionSensor

@export_group("Objects")
@export var arrow : Sprite2D
@export_subgroup("Markers")
@export var forward_marker : Marker2D
@export var neutral_marker : Marker2D
@export var reverse_marker : Marker2D
@export_group("Motion Feel")
@export var motion_curve : Curve   # design this in the inspector
@export var motion_duration : float = 0.4

var original_marker : Marker2D
var speed : float = 0.3
var _current_tween : Tween
var _current_target_marker : Marker2D
var _motion_start_y : float
var _motion_target_y : float

func forward(_delta : float) -> void:
	motion_duration = randf_range(0.7, 1.3)
	move_move(forward_marker, arrow)

func neutral(_delta : float) -> void:
	move_move(neutral_marker, arrow)

func reverse(_delta : float) -> void:
	move_move(reverse_marker, arrow)

func move_move(marker : Marker2D, object : Sprite2D) -> void:
	if marker == _current_target_marker:
		return
	_current_target_marker = marker
	original_marker = marker

	_motion_start_y = object.global_position.y
	_motion_target_y = marker.global_position.y

	if _current_tween:
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_method(_apply_curve_y.bind(object), 0.0, 1.0, motion_duration)

func _apply_curve_y(t : float, object : Sprite2D) -> void:
	var weight : float = motion_curve.sample(t)
	object.global_position.y = lerp(_motion_start_y, _motion_target_y, weight)
