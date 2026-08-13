extends Control
class_name UserInterface

@export_group("User Interface")
@export var end_day_btn : Button
@export var end_night_btn : Button
@export_subgroup("Inventory")
@export var inventory_lbl : Label
@export var inventory_grid : GridContainer
@export var inventory_button : PackedScene

func _ready() -> void:
	end_day_btn.pressed.connect(_on_end_day_btn_pressed)
	end_night_btn.pressed.connect(_on_end_night_btn_pressed)

func _on_end_day_btn_pressed() -> void:
	# Time set night
	get_tree().change_scene_to_file("res://GameState/Fishing/Fishing.tscn")

func _on_end_night_btn_pressed() -> void:
	# Time set night
	get_tree().change_scene_to_file("res://GameState/Market/game.tscn")

func set_items(items : Array[Item]) -> void:
	for i in items:
		var ib := inventory_button.instantiate()
		ib.held_item = i
		inventory_grid.add_child(ib)