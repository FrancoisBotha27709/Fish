extends Node
class_name WaterSplashParticle

@export var enter_particles : GPUParticles3D
@export var exit_particles : GPUParticles3D
@export var buoyancy_system_group : String = "buoyancy_system_group"

var _target : Node3D

func _ready() -> void:
	_target = get_parent()
	var systems := get_tree().get_nodes_in_group(buoyancy_system_group)
	if systems.is_empty():
		push_warning("WaterSplashParticles: no BuoyancySystem found in group '%s'." % buoyancy_system_group)
		return
	var buoyancy := systems[0]
	buoyancy.object_entered_water.connect(_on_entered)
	buoyancy.object_exited_water.connect(_on_exited)

func _on_entered(body: Node3D, world_pos: Vector3) -> void:
	if body != _target:
		return
	if enter_particles:
		enter_particles.global_position = world_pos
		enter_particles.restart()
		enter_particles.emitting = true

func _on_exited(body: Node3D, world_pos: Vector3) -> void:
	if body != _target:
		return
	if exit_particles:
		exit_particles.global_position = world_pos
		exit_particles.restart()
		exit_particles.emitting = true
