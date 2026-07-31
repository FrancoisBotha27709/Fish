extends CharacterBody3D
class_name Player

@export_group("User Interface")
@export var ui_node : UserInterface
@export_group("Data")
@export var invententory : Array[Item] = []

func _ready() -> void:
	UtilityStates.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed()
 
func _on_inventory_changed() -> void:
	if ui_node:
		ui_node.set_items(UtilityStates.items)
