extends Node3D
class_name FishSwimmer

@export_group("Movement")
@export var center := Vector3.ZERO
@export var radius := 10.0
@export var swim_speed := 5.0

@export_group("Random Variation")
@export var radius_variation := 2.5
@export var speed_variation := 1.2
@export var height_variation := 0.5
@export var radius_wobble := 0.8
@export var vertical_wobble := 0.25
@export var wobble_speed := 0.6

@export_group("Rotation")
@export var turn_smoothing := 5.0

var angle := 0.0

var _time := 0.0
var _individual_radius := 10.0
var _individual_speed := 5.0
var _base_height := 0.0
var _radius_phase := 0.0
var _vertical_phase := 0.0
var _initialized := false


func setup(
	p_center: Vector3,
	p_radius: float,
	p_speed: float
) -> void:
	center = p_center
	radius = p_radius
	swim_speed = p_speed

	_individual_radius = max(
		0.5,
		radius + randf_range(-radius_variation, radius_variation)
	)

	_individual_speed = max(
		0.5,
		swim_speed + randf_range(-speed_variation, speed_variation)
	)

	_base_height = randf_range(
		-height_variation,
		height_variation
	)

	_radius_phase = randf_range(0.0, TAU)
	_vertical_phase = randf_range(0.0, TAU)
	angle = randf_range(0.0, TAU)

	_initialized = true


func get_start_position() -> Vector3:
	return center + Vector3(
		cos(angle) * _individual_radius,
		_base_height,
		sin(angle) * _individual_radius
	)


func _process(delta: float) -> void:
	if not _initialized:
		return

	_time += delta

	# Each fish moves at its own angular speed.
	angle += (_individual_speed / _individual_radius) * delta

	# Slowly vary the orbit radius.
	var radius_offset := sin(
		_time * wobble_speed + _radius_phase
	) * radius_wobble

	var current_radius = max(
		0.5,
		_individual_radius + radius_offset
	)

	# Slowly vary the fish's height.
	var vertical_offset := sin(
		_time * wobble_speed * 1.35 + _vertical_phase
	) * vertical_wobble

	var target_position := center + Vector3(
		cos(angle) * current_radius,
		_base_height + vertical_offset,
		sin(angle) * current_radius
	)

	global_position = target_position

	# Tangent direction around the circle.
	var travel_direction := Vector3(
		-sin(angle),
		0.0,
		cos(angle)
	).normalized()

	if travel_direction.length_squared() <= 0.001:
		return

	var target_basis := Basis.looking_at(
		travel_direction,
		Vector3.UP
	)

	basis = basis.orthonormalized().slerp(
		target_basis,
		min(turn_smoothing * delta, 1.0)
	)
