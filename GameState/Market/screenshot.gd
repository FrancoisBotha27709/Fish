extends Node3D
class_name Screenshot

@export var anim_players : Array[AnimationPlayer]
@export var item_anim : AnimationPlayer
@export var item_container : Node3D

var item : Item = null

func _ready() -> void:
	pass

## Clears whatever is currently on display and shows active_item instead,
## replaying the drop-in animation from scratch. Safe to call repeatedly.
func start(active_item : Item) -> void:
	clear_item()

	item = active_item
	if item == null or item.outside_mesh_scene == null:
		return

	var item_scene := item.outside_mesh_scene.instantiate()
	item_container.add_child(item_scene)
	_freeze_wiggle(item_scene)

	for anim in anim_players:
		anim.stop()
		anim.play("stack_fall_3")

	if item_anim:
		item_anim.stop()
		item_anim.play("fall")


## Plays the "sold" animation on every anim_player that has one, and returns
## the longest resulting duration so the caller can time the preview's
## power-off to happen after the animation actually finishes.
func play_sold() -> float:
	var longest := 0.0
	for anim in anim_players:
		if anim.has_animation("sold"):
			anim.stop()
			anim.play("sold")
			longest = max(longest, anim.get_animation("sold").length)
	return longest


func clear_item() -> void:
	for child in item_container.get_children():
		child.queue_free()
	item = null

func _freeze_wiggle(root : Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0

		for i in surface_count:
			var mat := mesh_instance.get_active_material(i)
			if mat is ShaderMaterial:
				var frozen_mat := (mat as ShaderMaterial).duplicate() as ShaderMaterial
				frozen_mat.set_shader_parameter("wiggle_amount", 0.0)
				mesh_instance.set_surface_override_material(i, frozen_mat)

	for child in root.get_children():
		_freeze_wiggle(child)