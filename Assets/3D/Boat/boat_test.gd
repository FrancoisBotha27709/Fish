extends Node3D
class_name BoatModel

@export var rudder : MeshInstance3D
@export var anchor : MeshInstance3D
@export var prop : MeshInstance3D

@export_group("Lights")
@export var lights_z : Array[MeshInstance3D]
@export var lights_x : Array[MeshInstance3D]
@export_subgroup("Light Values")
@export var light_turn_speed : float = 4.0
@export var light_pan_limit : float = 80.0
@export var light_tilt_min : float = -30
@export var light_tilt_max : float = 60

#region Material
const BOAT_EMISSIVE_MATERIAL = preload("uid://6jva0rdtumww")
var base_emission_value : float = 4.5
var off_emission_value : float = 0.0

#endregion
var rudder_return_speed : float = 1.0

func rotate_prop(speed : float, delta : float, is_forward : bool) -> void:
	speed *= 1000
	if is_forward:
		prop.rotate_z(deg_to_rad(speed * delta))
	elif is_forward == false:
		prop.rotate_z(deg_to_rad(-speed * delta))
	else:
		prop.rotate_z(deg_to_rad(lerp(speed * delta, 0, delta)))

func turn_rudder(speed : float, turn_speed : float, delta : float) -> void:
	var _min_angle := -60
	var _max_angle := 60

	var min_rad = deg_to_rad(_min_angle)
	var max_rad = deg_to_rad(_max_angle)

	if speed != 0.0:
		rudder.rotation.y += (speed / (turn_speed * 100))
		rudder.rotation.y = clampf(rudder.rotation.y, min_rad, max_rad)

	else:
		rudder.rotation.y = move_toward(rudder.rotation.y, 0.0, rudder_return_speed * delta)

func aim_light(light_z : MeshInstance3D, light_x : MeshInstance3D, focus_point : Vector3, delta : float) -> void:
	# Yaw on z, measured in its parent's local space.
	# Forward is -Z, so both components get negated in atan2.
	var yaw_local : Vector3 = light_z.get_parent().to_local(focus_point) - light_z.position
	var target_yaw : float = atan2(-yaw_local.x, -yaw_local.z)
	target_yaw = clamp(target_yaw, deg_to_rad(-light_pan_limit), deg_to_rad(light_pan_limit))
	light_z.rotation.y = move_toward(light_z.rotation.y, target_yaw, light_turn_speed * delta)

	# Pitch on x, measured relative to light_z (accounts for yaw already applied).
	# Forward-facing distance is -z (since forward is -Z), not the unsigned length.
	var pitch_local : Vector3 = light_z.to_local(focus_point) - light_x.position
	var target_pitch := atan2(pitch_local.y, -pitch_local.z)
	target_pitch = clamp(target_pitch, deg_to_rad(light_tilt_min), deg_to_rad(light_tilt_max))
	light_x.rotation.x = move_toward(light_x.rotation.x, target_pitch, light_turn_speed * delta)

func aim_lights(focus_point : Vector3, delta : float) -> void:
	for i in min(lights_z.size(), lights_x.size()):
		aim_light(lights_z[i], lights_x[i], focus_point, delta)

func power_light(is_on : bool) -> void:
	var instance = BOAT_EMISSIVE_MATERIAL.get_instance_id()
	if is_on:
		instance.emission_energy_multiplier = base_emission_value
	else:
		instance.emission_energy_multiplier = off_emission_value
