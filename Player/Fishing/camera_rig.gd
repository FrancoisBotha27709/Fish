extends Node3D
class_name CameraRig

# Node3d that the camera points towards
@export var target: Node3D
# Optional dedicated look-at point (e.g. camera_target on the boat) - falls back to target if unset
@export var camera_target: Node3D
# CharacterBody - used for when target velocity is required
@export var character_target: CharacterBody3D

@export var ray_cast : RayCast3D

@export var camera: Camera3D

@export_group("Follow")
@export var follow_speed := 6.0
@export var target_height := 4.0

@export_group("Orbit")
@export var distance := 14.0
@export var pitch := 35.0
@export var mouse_sensitivity := 0.25
@export var orbit_smoothing := 5.0   ## how quickly mouse input eases into the actual orbit

@export_group("Camera Feel")
@export var camera_position_speed := 4.0   ## lag on the camera's own position vs the rig
@export var camera_rotation_speed := 5.0   ## lag on the camera's rotation catching up to look-at
@export var look_target_speed := 3.0       ## lag on the point the camera is looking at

@export_group("Recentering")
@export var recenter_delay := 2.0
@export var recenter_speed := 2.5
@export var minimum_move_speed := 0.25

var orbit_offset := 0.0
var _smoothed_orbit_offset := 0.0
var _smoothed_pitch := 35.0

var _look_point : Vector3
var _has_look_point := false

@onready var switch_anim: AnimationPlayer = $Camera3D/blockbench_export/AnimationPlayer

var _rotating := false
var _time_since_input := 0.0
var forward = false


func _ready() -> void:
	_smoothed_pitch = pitch
	if target:
		global_position = Vector3(target.global_position.x, target_height, target.global_position.z)
		_look_point = _get_look_target_position()
		_has_look_point = true


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


func _get_look_target_position() -> Vector3:
	if camera_target:
		return camera_target.global_position
	return target.global_position + Vector3.UP


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
		and character_target != null
		and _time_since_input > recenter_delay
		and Vector2(character_target.velocity.x, character_target.velocity.z).length() > minimum_move_speed
	):
		orbit_offset = lerp(orbit_offset, 0.0, 1.0 - exp(-recenter_speed * delta))

	# --- Ease the raw mouse-driven orbit/pitch values before using them ---
	# This is what removes the "tight/snappy" feel from mouse-look itself.
	_smoothed_orbit_offset = lerp(_smoothed_orbit_offset, orbit_offset, 1.0 - exp(-orbit_smoothing * delta))
	_smoothed_pitch = lerp(_smoothed_pitch, pitch, 1.0 - exp(-orbit_smoothing * delta))

	# Boat yaw + player orbit.
	var final_yaw := target.global_rotation.y + deg_to_rad(_smoothed_orbit_offset)

	var horizontal := Vector3(sin(final_yaw), 0.0, cos(final_yaw)) * distance
	var vertical := tan(deg_to_rad(_smoothed_pitch)) * distance

	var desired_camera_position := global_position + Vector3(horizontal.x, vertical, horizontal.z)

	# --- Camera position lags behind its orbit target instead of teleporting to it ---
	camera.global_position = camera.global_position.lerp(desired_camera_position, 1.0 - exp(-camera_position_speed * delta))

	# --- Look point itself lags too, so quick boat turns don't whip the view around ---
	var raw_look_point := _get_look_target_position()
	if not _has_look_point:
		_look_point = raw_look_point
		_has_look_point = true
	else:
		_look_point = _look_point.lerp(raw_look_point, 1.0 - exp(-look_target_speed * delta))

	# --- Rotation eases toward the look-at orientation instead of snapping ---
	var desired_transform := camera.global_transform.looking_at(_look_point, Vector3.UP)
	var current_quat := camera.global_transform.basis.get_rotation_quaternion()
	var desired_quat := desired_transform.basis.get_rotation_quaternion()
	var new_quat := current_quat.slerp(desired_quat, 1.0 - exp(-camera_rotation_speed * delta))
	camera.global_transform.basis = Basis(new_quat)


func get_ray_target() -> Vector3:
	if ray_cast.is_colliding():
		return ray_cast.get_collision_point()
	return ray_cast.to_global(ray_cast.target_position)
