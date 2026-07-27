extends Control
class_name UserInterface

@export_group("User Interface")
@export_subgroup("Inventory")
@export var inventory_lbl : Label
@export var inventory_grid : GridContainer
@export var inventory_button : PackedScene

func set_items(items : Array[Item]) -> void:
	for i in items:
		var ib := inventory_button.instantiate()
		ib.held_item = i
		inventory_grid.add_child(ib)
