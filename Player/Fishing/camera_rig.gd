extends Node3D
class_name CameraRig

@export var target: CharacterBody3D
@export var camera: Camera3D

@export_group("Follow")
@export var follow_speed := 6.0
@export var target_height := 4.0

@export_group("Orbit")
@export var distance := 14.0
@export var pitch := 35.0
@export var mouse_sensitivity := 0.25

@export_group("Recentering")
@export var recenter_delay := 2.0
@export var recenter_speed := 2.5
@export var minimum_move_speed := 0.25

var orbit_offset := 0.0
@onready var switch_anim: AnimationPlayer = $Camera3D/blockbench_export/AnimationPlayer

var _rotating := false
var _time_since_input := 0.0
var forward = false


func _ready() -> void:
	if target:
		global_position = Vector3(target.global_position.x, target_height, target.global_position.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = event.pressed

	if _rotating and event is InputEventMouseMotion:
		orbit_offset -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, 20.0, 70.0)

		_time_since_input = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("boat_forward"):
		if not forward:
			forward = true
			switch(forward)
	elif event.is_action_pressed("boat_reverse"):
		if forward:
			forward = false
			switch(forward)

func switch(value : bool) -> void:
	if value == false:
		switch_anim.play_backwards("pull_animation")
	elif value == true:
		switch_anim.play("pull_animation")


func _process(delta: float) -> void:
	if target == null:
		return

	# Smoothly follow the boat horizontally.
	var desired_position := Vector3(target.global_position.x, target_height, target.global_position.z)

	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_speed * delta))

	_time_since_input += delta

	# Return behind the boat after a short delay.
	if (
		not _rotating
		and _time_since_input > recenter_delay
		and Vector2(target.velocity.x, target.velocity.z).length() > minimum_move_speed):
		orbit_offset = lerp(orbit_offset, 0.0, 1.0 - exp(-recenter_speed * delta))

	# Boat yaw + player orbit.
	var final_yaw := target.global_rotation.y + deg_to_rad(orbit_offset)

	var horizontal := Vector3(sin(final_yaw), 0.0, cos(final_yaw)) * distance

	var vertical := tan(deg_to_rad(pitch)) * distance

	camera.global_position = global_position + Vector3(horizontal.x, vertical, horizontal.z)

	camera.look_at(target.global_position + Vector3.UP, Vector3.UP)
