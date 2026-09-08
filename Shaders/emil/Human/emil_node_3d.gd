@tool
extends Node3D
@export var ocean : MeshInstance3D

@export var current : SubViewport
@export var history_a : SubViewport
@export var history_b : SubViewport

## History A/ColorRect.material
@onready var material_a = $history_b/ColorRect.material
## History B/ColorRect.material
@onready var material_b = $history_b/ColorRect.material

var ocean_material : ShaderMaterial
var write_a : bool = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	ocean_material = ocean.get_surface_override_material(0)


	material_a.set_shader_parameter("delta", delta)
	material_b.set_shader_parameter("delta", delta)

	if (write_a):
		history_a.render_target_update_mode = SubViewport.UPDATE_ONCE
		history_b.render_target_update_mode = SubViewport.UPDATE_DISABLED

		ocean_material.set_shader_parameter("foam_map", history_a.get_texture())
	else:
		history_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		history_b.render_target_update_mode = SubViewport.UPDATE_ONCE

		ocean_material.set_shader_parameter("foam_map", history_b.get_texture())

	write_a = !write_a