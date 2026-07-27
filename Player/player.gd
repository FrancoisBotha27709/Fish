extends Node3D
class_name Player

@export_group("User Interface")
@export var ui_node : UserInterface
@export_group("Data")
@export var invententory : Array[Item] = []

func _ready() -> void:
	ui_node.set_items(invententory)
